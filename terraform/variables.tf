variable rds_credentials {
  type    = object({
    username = string
    password = string
    dbname = string
  })

  default = {
    username = "<username>"
    password = "<password>"
    dbname = "<dbname>"
  }
  
  description = "Master DB username, password and dbname for RDS"
}
