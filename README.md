# Terraform Project Scaffold

## About

A simple repository template for setting up Terraform projects quickly.

## Features

- Modular Terraform structure
- Environment-specific configuration
- Automated backend setup

## Getting Started

1. Clone the repository.
2. Update variables in `terraform.tfvars`.
3. Initialize and apply Terraform.

## Directory Structure

```
.
├── envs/
│   ├── dev/
│   ├── prod/
│   └── staging/
├── LICENSE
├── Makefile
├── modules/
└── README.md
```

`envs/`

Defines **environment-specific Terraform configurations**, such as `dev`, `staging`, `prod`, etc.


`modules`

Contains **resusable, self-contained Terraform modules**. Each subdirectory represents a single logical unit of infrastructure (e.g., VPC, EC2, S3)

## Requirements

- Terraform >= 1.0
- AWS CLI (if using AWS)
- [Other provider CLIs as needed]
- pre-commit [if using pre-commit with Git hooks]

## Usage

```sh
terraform init
terraform plan
terraform apply
```


## License

MIT License
