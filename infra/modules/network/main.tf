locals {
  name = "${var.project}-${var.environment}"

  # Subnets are derived from the VPC CIDR so a caller only has to pass one /16.
  # With a /16 in, cidrsubnet(.., 8, n) hands out /24s.
  #   public  -> 10.x.0.0/24,   10.x.1.0/24,   ...
  #   private -> 10.x.100.0/24, 10.x.101.0/24, ...
  public_subnet_cidrs  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 100)]

  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.azs)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${local.name}-public-${var.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${local.name}-private-${var.azs[count.index]}"
    Tier = "private"
  })
}

# NAT lives in the public subnets and gives the private subnets (Fargate tasks)
# outbound internet for image pulls and API calls, without making them reachable.
resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(var.tags, { Name = "${local.name}-nat-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, { Name = "${local.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${local.name}-public" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One route table per private subnet so each AZ can point at its own NAT.
resource "aws_route_table" "private" {
  count = length(var.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${local.name}-private-${var.azs[count.index]}" })
}

resource "aws_route" "private_default" {
  count = length(var.azs)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
