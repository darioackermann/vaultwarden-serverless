resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/26"
  tags = {
    Name = "vaultwarden-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = aws_vpc.vpc.cidr_block
  tags = {
    Name = "vaultwarden-subnet"
  }
}

resource "aws_default_route_table" "rtb" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id
  route {
    cidr_block = aws_vpc.vpc.cidr_block
    gateway_id = "local"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

data "aws_network_interface" "lambda_eni" {
  filter {
    name   = "interface-type"
    values = ["lambda"]
  }
  filter {
    name   = "group-id"
    values = [aws_security_group.lambda_sg.id]
  }

  depends_on = [aws_lambda_function.vaultwarden_function]
}

resource "aws_eip" "eip" {
  domain                    = "vpc"
  network_interface         = data.aws_network_interface.lambda_eni.id
  associate_with_private_ip = data.aws_network_interface.lambda_eni.private_ip
}