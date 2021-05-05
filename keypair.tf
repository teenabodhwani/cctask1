provider "aws" {
  region     = "ap-south-1"
  profile    = "fayazlinux"
}


resource "aws_security_group" "fayaz_grp" {
  name         = "fayaz_grp"
  description  = "allow ssh and httpd"
 
  ingress {
    description = "SSH Port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPD Port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "fayaz_sec_grp"
  }
}

variable ssh_key_name {
  default = "keywithtf"
}



resource "tls_private_key" "key-pair" {
  algorithm = "RSA"
	rsa_bits = 4096
}



resource "local_file" "private-key" {
 content = tls_private_key.key-pair.private_key_pem
 filename = "${var.ssh_key_name}.pem"
 file_permission = "0400"
}



resource "aws_key_pair" "deployer" {
 key_name   = var.ssh_key_name
 public_key = tls_private_key.key-pair.public_key_openssh
}



resource "aws_instance" "web" {
  ami           = "ami-005956c5f0f757d37"
  instance_type = "t2.micro"
  key_name = "${var.ssh_key_name}"
  security_groups = [ "fayaz_grp" ] 
  tags = {
    Name = "fayazOS"
  }

}

resource "null_resource" "nullremote1" {
 connection {
  type = "ssh"
  user = "ec2-user"
  private_key = file("${var.ssh_key_name}.pem")
  host = aws_instance.web.public_ip  
   }


 provisioner "remote-exec" {
 inline = [
   "sudo yum install httpd php git -y",
   "sudo service   httpd  restart",
   "sudo chkconfig httpd on",
    ]
  }
}






resource "aws_ebs_volume" "myvol" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "myvol"
  }
}



resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdd"
  volume_id   = "${aws_ebs_volume.myvol.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true
  depends_on = [ 
      aws_ebs_volume.myvol, 
      aws_instance.web ]
}



resource "null_resource" "nullremote2" {

  depends_on = [
      aws_volume_attachment.ebs_att,	 ]
  connection {
   type = "ssh"
   user = "ec2-user"
   private_key = file("${var.ssh_key_name}.pem")
   host = aws_instance.web.public_ip  
      }

  provisioner "remote-exec" {
   inline = [
   "sudo mkfs.ext4 /dev/xvdd",
   "sudo mount /dev/xvdd /var/www/html",
   "sudo rm -rf /var/www/html/*",
   "sudo git clone https://github.com/teenabodhwani/cctask1.git   /var/www/html/"
         ]
   }
}


resource "aws_s3_bucket" "kk-fayaz" {
  depends_on = [ 
     aws_volume_attachment.ebs_att, 
      ] 
  bucket = "kk-fayaz1"
  acl = "public-read"
 

  provisioner "local-exec" {
        command     = "git clone clone https://github.com/teenabodhwani/cctask1.git server_img"
    }


  
		
  provisioner "local-exec" {
		  when = destroy
		  command = "rmdir /s /q server_img"
		       }
	
}




resource "aws_s3_bucket_object" "object" {
   depends_on = [
      aws_s3_bucket.kk-fayaz, 
      ]


  bucket = aws_s3_bucket.kk-fayaz.bucket
 
  key    = "Sample.jpg"
  source = "server_img/Sample.jpg"
	  
  content_type = "image/jpg"
  acl    = "public-read"
  
}


locals { 
  s3_origin_id = "S3-${aws_s3_bucket.kk-fayaz.bucket}"
}






// Creating Origin Access Identity for CloudFront
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "kk-bucket"
}


resource "aws_cloudfront_distribution" "kklinux" {
  origin {
  domain_name = "${aws_s3_bucket.kk-fayaz.bucket_regional_domain_name}"
  origin_id = "${local.s3_origin_id}"
  
  s3_origin_config {
  origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
}
}

enabled = true
is_ipv6_enabled = true
comment = "kk-access"


default_cache_behavior {
  allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
  cached_methods = ["GET", "HEAD"]
  target_origin_id = "${local.s3_origin_id}"


  forwarded_values {
    query_string = false
      cookies {
        forward = "none"
      }
  }
  viewer_protocol_policy = "allow-all"
  min_ttl = 0
  default_ttl = 3600
  max_ttl = 86400
  }

# Cache behavior with precedence 0
ordered_cache_behavior {
path_pattern = "/content/immutable/*"
allowed_methods = ["GET", "HEAD", "OPTIONS"]
cached_methods = ["GET", "HEAD", "OPTIONS"]
target_origin_id = "${local.s3_origin_id}"
forwarded_values {
query_string = false
headers = ["Origin"]
cookies {
forward = "none"
}
}
min_ttl = 0
default_ttl = 86400
max_ttl = 31536000
compress = true
viewer_protocol_policy = "redirect-to-https"
}
# Cache behavior with precedence 1
ordered_cache_behavior {
path_pattern = "/content/*"
allowed_methods = ["GET", "HEAD", "OPTIONS"]
cached_methods = ["GET", "HEAD"]
target_origin_id = "${local.s3_origin_id}"
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
min_ttl = 0
default_ttl = 3600
max_ttl = 86400
compress = true
viewer_protocol_policy = "redirect-to-https"
}
price_class = "PriceClass_200"
restrictions {
  geo_restriction {
    restriction_type = "none"
}
}
tags = {
Environment = "production"
}
viewer_certificate {
cloudfront_default_certificate = true
}

connection {
   type = "ssh"
    user = "ec2-user"
    private_key = file("${var.ssh_key_name}.pem")
    host = aws_instance.web.public_ip  
       }
provisioner "remote-exec" {
     
      inline = [
          "sudo su << EOF",
          "echo \"<img src='http://${aws_cloudfront_distribution.kklinux.domain_name}/${aws_s3_bucket_object.object.key}' width='300' height='380'>\" >> /var/www/html/index.html",
          "EOF"
      ]
  }  
provisioner "local-exec" {
	    command = "start chorme  ${aws_instance.web.public_ip}"
  	}





retain_on_delete = true
}





