package main

import rego.v1

# Check AWS taggable resources carry the username tag
deny contains msg if {
	rc := input.resource_changes[_]
	some action in rc.change.actions
	action in {"create", "update"}
	startswith(rc.type, "aws_")
	after := rc.change.after
	after != null
	"tags_all" in object.keys(after)
	not after.tags_all.username
	msg := sprintf("AWS resource %s (%s) must carry a 'username' tag", [rc.address, rc.type])
}

# Check GCP labellable resources carry the username label
deny contains msg if {
	rc := input.resource_changes[_]
	some action in rc.change.actions
	action in {"create", "update"}
	startswith(rc.type, "google_")
	rc.type != "google_sql_database_instance"
	after := rc.change.after
	after != null
	"labels" in object.keys(after)
	not after.labels.username
	not after.terraform_labels.username
	msg := sprintf("GCP resource %s (%s) must carry a 'username' label", [rc.address, rc.type])
}

# Check Cloud SQL user_labels carries username
deny contains msg if {
	rc := input.resource_changes[_]
	some action in rc.change.actions
	action in {"create", "update"}
	rc.type == "google_sql_database_instance"
	after := rc.change.after
	after != null
	not after.settings[0].user_labels.username
	msg := sprintf("Cloud SQL %s must carry settings.user_labels.username", [rc.address])
}

# Forbid public RDS instances
deny contains msg if {
	rc := input.resource_changes[_]
	some action in rc.change.actions
	action in {"create", "update"}
	rc.type == "aws_db_instance"
	rc.change.after.publicly_accessible == true
	msg := sprintf("RDS instance %s must not be publicly_accessible", [rc.address])
}

# Forbid public Cloud SQL IPv4
deny contains msg if {
	rc := input.resource_changes[_]
	some action in rc.change.actions
	action in {"create", "update"}
	rc.type == "google_sql_database_instance"
	rc.change.after.settings[0].ip_configuration[0].ipv4_enabled == true
	msg := sprintf("Cloud SQL %s must not enable public IPv4", [rc.address])
}

# Forbid allUsers IAM bindings on GCP
deny contains msg if {
	rc := input.resource_changes[_]
	some action in rc.change.actions
	action in {"create", "update"}
	startswith(rc.type, "google_")
	contains(rc.type, "iam")
	rc.change.after.member == "allUsers"
	msg := sprintf("GCP IAM binding %s must never grant allUsers", [rc.address])
}

# Forbid unencrypted S3 buckets without KMS/AES256 or public access block disabled
deny contains msg if {
	rc := input.resource_changes[_]
	some action in rc.change.actions
	action in {"create", "update"}
	rc.type == "aws_s3_bucket_public_access_block"
	after := rc.change.after
	not (after.block_public_acls == true and after.block_public_policy == true and after.ignore_public_acls == true and after.restrict_public_buckets == true)
	msg := sprintf("S3 public access block %s must enable all four block flags", [rc.address])
}
