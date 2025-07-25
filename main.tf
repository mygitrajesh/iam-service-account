/**
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  iam_billing_pairs = flatten([
    for entity, roles in var.iam_billing_roles : [
      for role in roles : [
        { entity = entity, role = role }
      ]
    ]
  ])
  iam_folder_pairs = flatten([
    for entity, roles in var.iam_folder_roles : [
      for role in roles : [
        { entity = entity, role = role }
      ]
    ]
  ])
  iam_organization_pairs = flatten([
    for entity, roles in var.iam_organization_roles : [
      for role in roles : [
        { entity = entity, role = role }
      ]
    ]
  ])
  iam_project_pairs = flatten([
    for entity, roles in var.iam_project_roles : [
      for role in roles : [
        { entity = entity, role = role }
      ]
    ]
  ])
  iam_storage_pairs = flatten([
    for entity, roles in var.iam_storage_roles : [
      for role in roles : [
        { entity = entity, role = role }
      ]
    ]
  ])
  # https://github.com/hashicorp/terraform/issues/22405#issuecomment-591917758
  key = try(
    var.generate_key
    ? google_service_account_key.key["1"]
    : map("", null)
  , {})
  prefix                    = var.prefix != null ? "${var.prefix}-" : ""
  resource_email_static     = "${local.prefix}${var.name}@${var.project_id}.iam.gserviceaccount.com"
  resource_iam_email_static = "serviceAccount:${local.resource_email_static}"
  resource_iam_email        = local.service_account != null ? "serviceAccount:${local.service_account.email}" : local.resource_iam_email_static
  service_account = (
    var.service_account_create
    ? try(google_service_account.service_account.0, null)
    : try(data.google_service_account.service_account.0, null)
  )
  service_account_credential_templates = {
    for file, _ in local.public_keys_data : file => jsonencode(
      {
        type : "service_account",
        project_id : var.project_id,
        private_key_id : split("/", google_service_account_key.upload_key[file].id)[5]
        private_key : "REPLACE_ME_WITH_PRIVATE_KEY_DATA"
        client_email : local.resource_email_static
        client_id : local.service_account.unique_id,
        auth_uri : "https://accounts.google.com/o/oauth2/auth",
        token_uri : "https://oauth2.googleapis.com/token",
        auth_provider_x509_cert_url : "https://www.googleapis.com/oauth2/v1/certs",
        client_x509_cert_url : "https://www.googleapis.com/robot/v1/metadata/x509/${urlencode(local.resource_email_static)}"
      }
    )
  }
  public_keys_data = (
    var.public_keys_directory != ""
    ? {
      for file in fileset("${path.root}/${var.public_keys_directory}", "*.pem")
    : file => filebase64("${path.root}/${var.public_keys_directory}/${file}") }
    : {}
  )
}


data "google_service_account" "service_account" {
  count      = var.service_account_create ? 0 : 1
  project    = var.project_id
  account_id = "${local.prefix}${var.name}"
}

resource "google_service_account" "service_account" {
  count        = var.service_account_create ? 1 : 0
  project      = var.project_id
  account_id   = "${local.prefix}${var.name}"
  display_name = var.display_name
  description  = var.description
}

resource "google_service_account_key" "key" {
  for_each           = var.generate_key ? { 1 = 1 } : {}
  service_account_id = local.service_account.email
}

resource "google_service_account_key" "upload_key" {
  for_each           = local.public_keys_data
  service_account_id = local.service_account.email
  public_key_data    = each.value
}

resource "google_service_account_iam_binding" "roles" {
  for_each           = var.iam
  service_account_id = local.service_account.name
  role               = each.key
  members            = each.value
}

resource "google_billing_account_iam_member" "billing-roles" {
  for_each = {
    for pair in local.iam_billing_pairs :
    "${pair.entity}-${pair.role}" => pair
  }
  billing_account_id = each.value.entity
  role               = each.value.role
  member             = local.resource_iam_email
}

resource "google_folder_iam_member" "folder-roles" {
  for_each = {
    for pair in local.iam_folder_pairs :
    "${pair.entity}-${pair.role}" => pair
  }
  folder = each.value.entity
  role   = each.value.role
  member = local.resource_iam_email
}

resource "google_organization_iam_member" "organization-roles" {
  for_each = {
    for pair in local.iam_organization_pairs :
    "${pair.entity}-${pair.role}" => pair
  }
  org_id = each.value.entity
  role   = each.value.role
  member = local.resource_iam_email
}

resource "google_project_iam_member" "project-roles" {
  for_each = {
    for pair in local.iam_project_pairs :
    "${pair.entity}-${pair.role}" => pair
  }
  project = each.value.entity
  role    = each.value.role
  member  = local.resource_iam_email
}

resource "google_storage_bucket_iam_member" "bucket-roles" {
  for_each = {
    for pair in local.iam_storage_pairs :
    "${pair.entity}-${pair.role}" => pair
  }
  bucket = each.value.entity
  role   = each.value.role
  member = local.resource_iam_email
}
