# About the Project

This Project was build using AWS services, terraform and ansible to create scalable wordpress website and database.

Also using some premium services for security as WAF, Route53 and low latency as CloudFront for understanding the full picture of the cloud enviroment.

# Architecture:  
<img src="./AWS_WP_EFS.png" width="650" height="850">


## Scenario

1. Users accessing site url (Route53) are redericted to the closest AWS data centers. (Edge Locations)
2. At this data centers CloudFront is ready to serve the user with cached website content to lower loading latency.
3. Users are passed through the Web Application Firewall before reaching the servers in order to protect them from exposure and attacks.
4. Elastic Load Balancer is automatically distributes the Users to the 2 Availability Zones of the application servers.
5. Both of the Wordpress servers are using the Master RDS mysql database.
6. In the event of the Master RDS failure, the Standby RDS instance is triggered in a second to achieve fault tolerance.
7. CloudWatch monitors CPU usage of ec2 servers, if it's over 60% it alarm the Auto Scaling Group to launch another instance to support the load.
8. After the peak, if ec2 server cpu usage is under 20% the instance is automatically terminated by the ASG.
9. Website files are saved to Elastic File System, which is natively integrated with AWS Backup .
10. AWS Backup is where you can schdule and monitor all recent backups and restore activity.
11. NAT service provides the private subnets with resources and services from the internet supporting the Website operation, but external services cannot initiate a connection with those instances.
12. CloudTrail monitors and records user activity and events to logs, improve security posture or prove compliance with regulations.
