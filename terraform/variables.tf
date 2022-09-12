variable rds_credentials {
  type    = object({
    username = "admin"
    password = "Password123"
    dbname = "WP-DB"
  })

  default = {
    username = "<username>"
    password = "<password>"
    dbname = "<dbname>"
  }
  
  description = "Master DB username, Password and Database name for RDS"
}
