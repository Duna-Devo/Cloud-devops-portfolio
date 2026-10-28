# Flags resources shared outside this AWS account (public buckets, cross-account roles)
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "stage8-analyzer"
  type          = "ACCOUNT"
}
