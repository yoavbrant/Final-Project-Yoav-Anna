data "aws_availability_zones" "available" {}
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.${100 + count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-subnet-${count.index + 1}" }
}
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.project_name}-private-subnet-${count.index + 1}" }
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}
resource "aws_eip" "nat" {
  count = 2
  # Using domain = "vpc" is deprecated, but required for older AWS providers.
  # For newer providers, just 'resource "aws_eip" "nat" { count = 2 }' is sufficient.
  vpc = true
}
resource "aws_nat_gateway" "main" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.project_name}-nat-gw-${count.index + 1}" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = { Name = "${var.project_name}-private-rt-${count.index + 1}" }
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}
resource "random_password" "db_password" {
  length  = 16
  special = false
}
resource "aws_db_subnet_group" "rds" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
}
resource "aws_db_instance" "main" {
  identifier             = "${var.project_name}-db"
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "13"
  instance_class         = "db.t3.micro"
  db_name                = "statuspage"
  username               = "statuspage"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  multi_az               = true
}
resource "aws_efs_file_system" "static" {
  creation_token   = "${var.project_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true
  tags             = { Name = "${var.project_name}-efs-static" }
}
resource "aws_efs_mount_target" "main" {
  count           = 2
  file_system_id  = aws_efs_file_system.static.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}
resource "aws_security_group" "alb" {
  name   = "${var.project_name}-alb-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"]; }
  ingress { from_port = 443; to_port = 443; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"]; }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]; }
}
resource "aws_security_group" "eks_nodes" {
  name   = "${var.project_name}-eks-nodes-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; security_groups = [aws_security_group.alb.id]; }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]; }
}
resource "aws_security_group" "rds" {
  name   = "${var.project_name}-rds-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 5432; to_port = 5432; protocol = "tcp"; security_groups = [aws_security_group.eks_nodes.id]; }
}
resource "aws_security_group" "efs" {
  name   = "${var.project_name}-efs-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 2049; to_port = 2049; protocol = "tcp"; security_groups = [aws_security_group.eks_nodes.id]; }
}
data "aws_iam_policy_document" "eks_assume_role" {
  statement { actions = ["sts:AssumeRole"]; principals { type = "Service"; identifiers = ["eks.amazonaws.com"]; } }
}
resource "aws_iam_role" "eks_cluster" {
  name               = "${var.project_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}
data "aws_iam_policy_document" "nodes_assume_role" {
  statement { actions = ["sts:AssumeRole"]; principals { type = "Service"; identifiers = ["ec2.amazonaws.com"]; } }
}
resource "aws_iam_role" "eks_nodes" {
  name               = "${var.project_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume_role.json
}
resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}
resource "aws_iam_role_policy_attachment" "eks_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}
resource "aws_eks_cluster" "main" {
  name     = var.project_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.28"
  vpc_config { subnet_ids = concat(aws_subnet.public, aws_subnet.private) }
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = [for s in aws_subnet.private : s.id]
  instance_types  = ["t3.small"]
  scaling_config { desired_size = 4; min_size = 2; max_size = 4; }
  update_config { max_unavailable = 1 }
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ecr_readonly,
  ]
}
resource "aws_secretsmanager_secret" "app_secrets" { name = "${var.project_name}/app-secrets" }
resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  secret_id     = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    DATABASE_PASSWORD = random_password.db_password.result
    SECRET_KEY        = "ZcyS%a_0^PAwPk4ZC5g@SUp-Y&Jhb^ER+_SL*q-glehDZmS$OZ"
  })
}
# This creates the Hosted Zone in Route 53. It does not register the domain name itself.
resource "aws_route53_zone" "main" {
  name = var.domain_name
}
resource "aws_acm_certificate" "main" {
  domain_name       = "${var.subdomain_name}.${var.domain_name}"
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}
resource "aws_route53_record" "cert_validation" {
  for_each = { for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => { name = dvo.resource_record_name, record = dvo.resource_record_value, type = dvo.resource_record_type } }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
