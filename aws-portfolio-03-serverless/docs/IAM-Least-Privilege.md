# Phase 03 — IAM Least Privilege Redesign

## Before: one shared execution role

All four Lambda functions (`create_entry`, `list_entries`, `update_entry`,
`delete_entry`) originally assumed the same IAM role,
`aws-portfolio-03-serverless-lambda-exec`, which carried a single inline
policy granting the full DynamoDB CRUD set to all of them:

```
lambda_exec (shared by 4 functions)
└── dynamodb:PutItem, GetItem, Query, UpdateItem, DeleteItem
    on arn:...:table/aws-portfolio-03-serverless-entries
```

The resource was already scoped to one table (not `*`), which is a
reasonable first step. But the **action** set was not scoped per function —
every function could call every DynamoDB write/read operation, regardless
of what its own handler actually does. That's the shape a shared role tends
to take over time: it's just easier to add one more `Action` to the one
existing policy than to reason about who needs what.

## Why this matters

A shared, over-permissioned role is a blast-radius problem, not a
theoretical one. If `list_entries` (a read-only listing endpoint) were ever
compromised — a dependency vulnerability, a bad deploy, a logic bug that
lets user input reach somewhere it shouldn't — the attacker inherits
whatever that function's role can do. With the shared role, that includes
`DeleteItem` on the entire table, even though `list_entries` never deletes
anything. The IAM policy was silently wider than the code it protected.

This is also the difference between "it passes a security checklist" and
"it reflects what the code does": scoping by resource ARN is necessary but
not sufficient. Least privilege means the policy is a direct, verifiable
statement of what the code needs — not what's convenient to grant once and
forget about.

## Redesign: one role per function, scoped to its actual DynamoDB call

Each handler was read to find out exactly which DynamoDB API it calls —
not inferred from the function name, verified in the source:

| Function | DynamoDB call | Source |
|---|---|---|
| `create_entry` | `table.put_item(...)` | `backend/lambda/create_entry/handler.py:40` |
| `list_entries` | `table.query(...)` | `backend/lambda/list_entries/handler.py:15` |
| `update_entry` | `table.update_item(...)` | `backend/lambda/update_entry/handler.py:24` |
| `delete_entry` | `table.delete_item(...)` | `backend/lambda/delete_entry/handler.py:14` |

None of the handlers call more than one DynamoDB action. `update_entry` and
`delete_entry` don't issue a separate `GetItem` to check ownership first —
they fold that check into the mutating call itself
(`ConditionExpression="attribute_exists(userId)"` keyed by the caller's own
`userId`), so no read permission is needed for either.

Each function now gets its own role, trust policy, and inline policy
containing exactly one `Action`:

```
create_entry-exec  → dynamodb:PutItem     (+ AWSLambdaBasicExecutionRole for logs)
list_entries-exec  → dynamodb:Query       (+ AWSLambdaBasicExecutionRole for logs)
update_entry-exec  → dynamodb:UpdateItem  (+ AWSLambdaBasicExecutionRole for logs)
delete_entry-exec  → dynamodb:DeleteItem  (+ AWSLambdaBasicExecutionRole for logs)
```

Resource scope is unchanged (still the single `entries` table ARN, never
`*`); what changed is the action set per function.

## Implementation

Both IaC implementations were updated to keep them in sync (per the
project's [dual-implementation strategy](../../README.md#iac-strategy)):

- **Terraform** (`infrastructure/terraform/lambda.tf`, deployed) — the
  identical trust policy is factored into one
  `data "aws_iam_policy_document" "lambda_assume_role"` reused by all four
  `aws_iam_role` resources, to avoid repeating the same JSON four times.
  Each function still gets its own explicit `aws_iam_role` /
  `aws_iam_role_policy_attachment` / `aws_iam_role_policy` block — no
  `for_each` map — to match this file's existing style of writing each of
  the four functions out individually rather than looping over them.
- **CloudFormation** (`infrastructure/cloudformation/lambda.yaml`,
  reference only, never deployed) — mirrors the same four-role structure.
  CloudFormation has no data-source equivalent, so the trust policy is
  repeated once per role, matching this template's existing verbatim style.

## Verification

```
terraform validate   # Success: the configuration is valid.
terraform plan        # 12 to add, 4 to change, 3 to destroy
```

The plan is exactly what the redesign should produce and nothing else:

- **+12**: 4 new roles, 4 new `AWSLambdaBasicExecutionRole` attachments, 4
  new inline DynamoDB policies (one `Action` each, verified against the
  table above)
- **~4**: the 4 `aws_lambda_function` resources updated in place to point
  `role` at their new dedicated role ARN — no other attribute changes
- **-3**: the old shared role, its log policy attachment, and its
  five-action inline policy

No DynamoDB, API Gateway, Cognito, or frontend resources appear in the
plan — this change is contained entirely to Lambda IAM, as intended.

`terraform apply` was run after this verification. All 12 additions
succeeded and the 3 old shared-role resources were destroyed. Post-apply
checks:

```
aws lambda get-function-configuration --function-name ...   # role ARN → *-exec per function, for all 4
aws iam get-role-policy --role-name *-exec ...               # exactly one Action each, matching the table above
aws iam get-role --role-name aws-portfolio-03-serverless-lambda-exec   # NoSuchEntity — old shared role is gone
```

A synthetic invoke of `list_entries` (a `Query` for a nonexistent test
`userId`, read-only, no data mutation) returned `{"statusCode": 200,
"body": "[]"}` — confirming the new role's single-action policy actually
works end-to-end, not just that it exists. The live site
(`journal.daoxiao.org`, 200) and API Gateway endpoint (`/entries`
unauthenticated, 401 as expected from the JWT authorizer) were also
checked and are unaffected.

## Dead IAM user config removed along the way

While validating this change, `terraform plan` surfaced an unrelated,
pre-existing error: `data "aws_iam_user" "github_actions"` in `iam.tf`
failed because the IAM user `github-actions-portfolio-01` no longer
exists — left over from the switch to OIDC-based deploy authentication
(commit `5c5b571`, "Authenticate deployments with OIDC instead of a
stored access key"). Confirmed via `aws iam get-user` (404) and by
checking both `deploy-03-serverless.yml` and `deploy-03-frontend.yml`,
which already authenticate via OIDC (`AWS_DEPLOY_ROLE_ARN`,
`shared-infra/github-oidc/main.tf`) and already grant the same
`lambda:UpdateFunctionCode` / S3 / CloudFront permissions this file was
trying to attach to the deleted user. The two `aws_iam_user_policy`
resources that depended on it had already been silently dropped from
Terraform state on refresh (their parent user is gone, so AWS had
already deleted the inline policies along with it). Since this was a
hard blocker for `plan`/`apply`, not just dead weight, `iam.tf` and its
now-unused `github_actions_iam_user_name` variable were removed as part
of this change, and the stale comment in `deploy-03-serverless.yml`
pointing at `iam.tf` was corrected to describe the actual OIDC setup.
