data "aws_ami" "centos7" {
  # See http://cavaliercoder.com/blog/finding-the-latest-centos-ami.html
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS Linux 7 x86_64 HVM EBS *"]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  filter {
    name = "root-device-type"
    values = ["ebs"]
  }

  owners = ["679593333241"]
}

resource "aws_instance" "mgmt" {
  ami           = data.aws_ami.centos7.id
  instance_type = var.management_shape
  vpc_security_group_ids = [aws_security_group.mgmt.id]
  subnet_id = aws_subnet.vpc_subnetwork.id
  associate_public_ip_address = "true"
  iam_instance_profile = aws_iam_instance_profile.describe_tags.id

  user_data = data.template_file.bootstrap-script.rendered
  key_name = aws_key_pair.ec2-user.key_name

  depends_on = [aws_efs_mount_target.shared, aws_key_pair.ec2-user, aws_route53_record.shared, aws_route.internet_route]

  connection {
    type        = "ssh"
    user        = "centos"
    private_key = data.local_file.ssh_private_key.content
    host        = aws_instance.mgmt.public_ip
  }

  provisioner "file" {
    destination = "/tmp/shapes.yaml"
    source      = "${path.module}/files/shapes.yaml"
  }

  provisioner "file" {
    destination = "/tmp/startnode.yaml"
    content     = data.template_file.startnode-yaml.rendered
  }

  provisioner "file" {
    destination = "/tmp/aws-credentials.csv"
    source      = "/home/matt/.aws/credentials"
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "echo Terminating any remaining compute nodes",
      "if systemctl status slurmctld >> /dev/null; then",
      "sudo -u slurm /usr/local/bin/stopnode \"$(sinfo --noheader --Format=nodelist:10000 | tr -d '[:space:]')\" || true",
      "fi",
      "sleep 5",
      "echo Node termination request completed",
    ]
  }

  tags = {
    Name = "mgmt-${local.cluster_id}"
    cluster = local.cluster_id
  }
}

resource "aws_key_pair" "ec2-user" {
  key_name   = "ec2-user-${local.cluster_id}"
  public_key = data.local_file.ssh_public_key.content
}

resource "aws_route53_record" "mgmt" {
  zone_id = aws_route53_zone.cluster.zone_id
  name    = "mgmt.${aws_route53_zone.cluster.name}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.mgmt.private_ip]
}
