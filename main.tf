terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
# Dynamically look up the latest official Ubuntu 22.04 LTS AMI in us-east-1
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # The official AWS Account ID owned by Canonical/Ubuntu

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "resume_sg" {
  name        = "resume-web-firewall"
  description = "Allow SSH and HTTP traffic"

  # Door 1: Allow SSH inbound from anywhere so we can configure it
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Door 2: Allow HTTP web traffic inbound so we can see the resume website
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Rules: Allow the server to talk to the internet to download updates
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 1. Generate a secure private key on your Mac automatically
resource "tls_private_key" "rsa_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Register that key pair with AWS so the server accepts it
resource "aws_key_pair" "deployer_key" {
  key_name   = "resume-server-key"
  public_key = tls_private_key.rsa_key.public_key_openssh
}

# 3. Save the private key securely to your local folder so Ansible can use it
resource "local_file" "private_key" {
  content         = tls_private_key.rsa_key.private_key_pem
  filename        = "${path.module}/resume-key.pem"
  file_permission = "0600" # Restricts permissions so only your Mac user can read it
}

# 4. Launch the actual EC2 Server Instance
resource "aws_instance" "resume_server" {
  ami           = data.aws_ami.ubuntu.id # This automatically injects the latest valid ID
  instance_type = "t3.micro"             # Free-tier eligible server size

  # Link the firewall we built earlier
  vpc_security_group_ids = [aws_security_group.resume_sg.id]

  # Inject our deployment key for login
  key_name               = aws_key_pair.deployer_key.key_name

  tags = {
    Name = "Automated-Resume-Server"
  }
}

# 5. Output the Server's IP address to the screen when finished
output "server_public_ip" {
  value       = aws_instance.resume_server.public_ip
  description = "The public IP address of your new web server"
}
