resource "aws_efs_file_system" "fs" {
  encrypted       = true
  throughput_mode = "elastic"

  tags = {
    Name = "vaultwarden"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_efs_mount_target" "fs" {
  file_system_id  = aws_efs_file_system.fs.id
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.lambda_sg.id]
}

resource "aws_efs_access_point" "ap" {
  file_system_id = aws_efs_file_system.fs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0777"
    }
  }

}

resource "aws_efs_backup_policy" "policy" {
  file_system_id = aws_efs_file_system.fs.id
  backup_policy {
    status = "ENABLED"
  }
}