provider "aws" {
  region     = ""
  access_key = ""
  secret_key = ""
  token = ""
}
module "myip" {
  source  = "4ops/myip/http"
  version = "1.0.0"
}

data "template_file" "user_data" {
  template = file("./install.sh")
}

resource "aws_instance" "for_ami" {
  ami           = data.aws_ami.amzlinux2.id
  instance_type = "t2.micro"
  user_data = data.template_file.user_data.rendered
  tags = {
    Name = "Delete_me"
  }
}

resource "aws_ami_from_instance" "apache_php" {
  name               = "apache_php"
  source_instance_id = aws_instance.for_ami.id
}

resource "aws_vpc" "myvpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "MyVPC"
  }
}

resource "aws_subnet" "eu-west-2a" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "eu-west-2a"
  }
}

resource "aws_subnet" "eu-west-2b" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "eu-west-2b"
  }
}

resource "aws_internet_gateway" "mygw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "MyIG"
  }
  depends_on = [aws_vpc.myvpc]
}

resource "aws_route" "route_to_ig" {
  route_table_id         = aws_vpc.myvpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.mygw.id
  depends_on             = [aws_internet_gateway.mygw, aws_vpc.myvpc]
}

resource "aws_route_table_association" "eu-west-2a" {
  subnet_id      = aws_subnet.eu-west-2a.id
  route_table_id = aws_vpc.myvpc.main_route_table_id
}

resource "aws_route_table_association" "eu-west-2b" {
  subnet_id      = aws_subnet.eu-west-2b.id
  route_table_id = aws_vpc.myvpc.main_route_table_id
}

resource "aws_efs_file_system" "myefs" {
  encrypted = true
  tags = {
    Name = "MyEFS"
  }
}

resource "aws_efs_mount_target" "eu-west-2a" {
  file_system_id  = aws_efs_file_system.myefs.id
  subnet_id       = aws_subnet.eu-west-2a.id
  security_groups = [aws_security_group.SG_for_EFS.id]
  depends_on      = [aws_efs_file_system.myefs, aws_security_group.SG_for_EFS]
}

resource "aws_efs_mount_target" "eu-west-2b" {
  file_system_id  = aws_efs_file_system.myefs.id
  subnet_id       = aws_subnet.eu-west-2b.id
  security_groups = [aws_security_group.SG_for_EFS.id]
  depends_on      = [aws_efs_file_system.myefs, aws_security_group.SG_for_EFS]
}

resource "aws_security_group" "SG_for_EC2" {
  name        = "SG_for_EC2"
  description = "Allow 80, 443, 22 port inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "TLS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${module.myip.address}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "SG_for_RDS" {
  name        = "SG_for_RDS"
  description = "Allow MySQL inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description     = "RDS from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.SG_for_EC2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_security_group.SG_for_EC2]
}

resource "aws_security_group" "SG_for_EFS" {
  name        = "SG_for_EFS"
  description = "Allow NFS inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description     = "NFS from EC2"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.SG_for_EC2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_security_group.SG_for_EC2]
}

resource "aws_security_group" "SG_for_ELB" {
  name        = "SG_for_ELB"
  description = "Allow traffic for ELB"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "Allow all inbound traffic on the 80 port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.SG_for_EC2.id]
  }
  depends_on = [aws_security_group.SG_for_EC2]
}

resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = [aws_subnet.eu-west-2a.id, aws_subnet.eu-west-2b.id]
}

resource "aws_db_instance" "mysql" {
  identifier = "mysql"
  engine     = "mysql"
  engine_version                  = "5.7.33"
  instance_class                  = "db.t2.micro"
  db_subnet_group_name            = aws_db_subnet_group.default.name
  enabled_cloudwatch_logs_exports = ["general", "error"]
  db_name                         = var.rds_credentials.dbname
  username                        = var.rds_credentials.username
  password                        = var.rds_credentials.password
  allocated_storage               = 20
  max_allocated_storage           = 0
  backup_retention_period         = 7
  backup_window                   = "00:00-00:30"
  maintenance_window              = "Sun:21:00-Sun:21:30"
  storage_type                    = "gp2"
  vpc_security_group_ids          = [aws_security_group.SG_for_RDS.id]
  skip_final_snapshot             = true
  depends_on                      = [aws_security_group.SG_for_RDS, aws_db_subnet_group.default]
}

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "myKey"       # Create a "myKey" to AWS!!
  public_key = tls_private_key.pk.public_key_openssh

  provisioner "local-exec" { # Create a "myKey.pem" to your computer!!
    command = "echo '${tls_private_key.pk.private_key_pem}' > ~/.ssh/myKey | chmod 400 ~/.ssh/myKey"
  }
}


# AWS EC2 Instance Key Pair
variable "instance_keypair" {
  description = "AWS EC2 Key pair that need to be associated with EC2 Instance"
  type = string
  default = "myKey"
}

resource "aws_launch_configuration" "my_conf" {
  name_prefix                 = "My Launch Config with WP"
  image_id                    = aws_ami_from_instance.apache_php.id
  instance_type               = "t2.micro"
  key_name                    = var.instance_keypair
  security_groups             = [aws_security_group.SG_for_EC2.id]
  associate_public_ip_address = true
  root_block_device {
    volume_type = "gp2"
    volume_size = 8
    encrypted   = false
  }
  user_data  = <<EOF
#!/bin/bash
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.myefs.dns_name}:/ /var/www/html
EOF
  depends_on = [aws_security_group.SG_for_EC2, aws_ami_from_instance.apache_php]
}

resource "aws_autoscaling_group" "my_asg" {
  name_prefix               = "my_asg"
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  launch_configuration      = aws_launch_configuration.my_conf.name
  vpc_zone_identifier       = [aws_subnet.eu-west-2a.id, aws_subnet.eu-west-2b.id]
  load_balancers            = [aws_elb.my_elb.name]
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_elb.my_elb, aws_launch_configuration.my_conf, aws_efs_mount_target.eu-west-2a, aws_efs_mount_target.eu-west-2b]
}

resource "aws_elb" "my_elb" {
  name            = "My-ELB"
  security_groups = [aws_security_group.SG_for_ELB.id]
  subnets         = [aws_subnet.eu-west-2a.id, aws_subnet.eu-west-2b.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    target              = "TCP:80"
    interval            = 20
  }

  cross_zone_load_balancing = true
  idle_timeout              = 60
  depends_on                = [aws_security_group.SG_for_ELB]
}

resource "local_file" "wp_config" {
  filename = "../ansible/roles/wordpress/files/wp-config.php"
  content = templatefile("./wp-config.tmpl", {
    database_name = "WP_DB"
    username      = "admin"
    password      = "Password123"
    db_host       = aws_db_instance.mysql.endpoint
  })
  depends_on = [aws_db_instance.mysql, aws_autoscaling_group.my_asg]
}

data "aws_instances" "my_inst" {

  filter {
    name   = "image-id"
    values = [aws_ami_from_instance.apache_php.id]
  }
  depends_on = [aws_autoscaling_group.my_asg]
}

resource "local_file" "servers" {
  filename = "../ansible/hosts"
  content = templatefile("./servers.tmpl", {
    ip = data.aws_instances.my_inst.public_ips[0]
  })
}

resource "null_resource" "ansible" {
  provisioner "local-exec" {
    working_dir = "../ansible"
    command     = "ansible-playbook -i hosts wp.yaml"
  }
  depends_on = [local_file.servers, local_file.wp_config]
}

resource "aws_cloudwatch_metric_alarm" "cpuover60" {
  alarm_name                = "cpuover60"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "60"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
  alarm_actions     = [aws_autoscaling_policy.scale_out_one.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpuunder20" {
  alarm_name                = "cpuunder20"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "20"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
  alarm_actions     = [aws_autoscaling_policy.scale_in_one.arn]
}

resource "aws_autoscaling_policy" "scale_out_one" {
  name                   = "add_one_unit_policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.my_asg.name
}

resource "aws_autoscaling_policy" "scale_in_one" {
  name                   = "delete_one_unit_policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.my_asg.name
}

# Get latest AMI ID for Amazon Linux2 OS
# Get Latest AWS AMI ID for Amazon2 Linux
data "aws_ami" "amzlinux2" {
  most_recent = true
  owners = [ "amazon" ]
  filter {
    name = "name"
    values = [ "amzn2-ami-hvm-*-gp2" ]
  }
  filter {
    name = "root-device-type"
    values = [ "ebs" ]
  }
  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }
  filter {
    name = "architecture"
    values = [ "x86_64" ]
  }
}
