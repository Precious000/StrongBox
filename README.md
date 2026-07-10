# StrongBox

StrongBox is a lightweight, Vault-inspired secret management system built with Bash, Docker, and PostgreSQL. It provides secure secret storage, Shamir Secret Sharing for initialization, token-based authentication, encrypted secret storage, audit logging, dynamic PostgreSQL credentials, lease management, and a simple leader-election mechanism for high availability.

## Features

* Secure secret storage using AES-256 encryption
* Shamir Secret Sharing for secure initialization and unsealing
* Token-based authentication and authorization
* Policy-based access control
* Versioned secret storage
* Dynamic PostgreSQL credential generation
* Lease creation, renewal, and revocation
* Comprehensive audit logging
* Multi-node deployment with basic leader election
* Nginx reverse proxy
* Docker Compose deployment
* RESTful HTTP API

---

## Project Architecture


<img width="1536" height="1024" alt="ChatGPT Image Jul 10, 2026, 05_34_17 AM" src="https://github.com/user-attachments/assets/da1e4e7e-9be8-4c3d-b31a-f645fa4591da" />


## Technologies Used

* Bash
* Docker
* Docker Compose
* PostgreSQL
* Nginx
* OpenSSL
* Python (Shamir Secret Sharing)
* Netcat
* JSON
* Linux

---

## Project Structure

```
StrongBox/
├── bin/
├── lib/
├── nginx/
├── data/
├── Dockerfile.node
├── compose.yaml
├── README.md
└── .gitignore
```

---

## Getting Started

### Clone the repository

```bash
git clone https://github.com/<your-username>/StrongBox.git
cd StrongBox
```

### Build the containers

```bash
docker compose build
```

### Start the services

```bash
docker compose up -d
```

### Check container status

```bash
docker ps
```

---

## API Endpoints

### System

| Method | Endpoint         | Description          |
| ------ | ---------------- | -------------------- |
| GET    | `/v1/sys/health` | Health check         |
| POST   | `/v1/sys/init`   | Initialize StrongBox |
| POST   | `/v1/sys/unseal` | Unseal the vault     |
| POST   | `/v1/sys/seal`   | Seal the vault       |

### Authentication

| Method | Endpoint          |
| ------ | ----------------- |
| POST   | `/v1/auth/login`  |
| POST   | `/v1/auth/revoke` |
| GET    | `/v1/auth/self`   |

### Secrets

| Method | Endpoint             |
| ------ | -------------------- |
| PUT    | `/v1/secrets/{path}` |
| GET    | `/v1/secrets/{path}` |
| DELETE | `/v1/secrets/{path}` |

### Policies

| Method | Endpoint              |
| ------ | --------------------- |
| PUT    | `/v1/policies/{name}` |
| GET    | `/v1/policies/{name}` |

### Dynamic Credentials

| Method | Endpoint                      |
| ------ | ----------------------------- |
| GET    | `/v1/dynamic-postgres/{role}` |

### Leases

| Method | Endpoint                 |
| ------ | ------------------------ |
| POST   | `/v1/leases/{id}/renew`  |
| POST   | `/v1/leases/{id}/revoke` |

### Audit

| Method | Endpoint    |
| ------ | ----------- |
| GET    | `/v1/audit` |

---

## Security Features

* AES-256 encrypted secret storage
* Shamir Secret Sharing
* Policy-based authorization
* Token authentication
* Secret versioning
* Audit trail
* Dynamic database credentials
* Lease expiration and revocation

---

## Future Improvements

* TLS certificate automation
* Kubernetes deployment
* Automatic node discovery
* Metrics and monitoring with Prometheus
* Grafana dashboards
* Web-based management dashboard
* Multi-datacenter replication
* Backup and disaster recovery

---

## Learning Objectives

This project was built to explore:

* Secure secret management
* Distributed systems concepts
* Leader election
* Cryptography fundamentals
* Docker container orchestration
* Reverse proxy configuration
* Authentication and authorization
* Infrastructure automation

---

## License

This project is released under the MIT License.
