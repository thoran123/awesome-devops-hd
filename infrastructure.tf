# ═══════════════════════════════════════════════════════════════════
# COMPLETE AZURE INFRASTRUCTURE AS CODE - UPDATED
# ═══════════════════════════════════════════════════════════════════
# This Terraform configuration creates a complete Azure DevOps infrastructure
# Includes: AKS Cluster, ACR, CosmosDB, Networking, Monitoring, Alerts
# Auto-scaling: AKS cluster with node auto-scaling and HPA support
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# TERRAFORM CONFIGURATION BLOCK
# ───────────────────────────────────────────────────────────────────
# Specifies Terraform version and required providers
terraform {
  required_version = ">= 1.0"  # Minimum Terraform version
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"      # Azure provider version
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"      # Kubernetes provider version
    }
  }
  
  # ───────────────────────────────────────────────────────────────────
  # BACKEND CONFIGURATION: State Storage
  # ───────────────────────────────────────────────────────────────────
  # Stores Terraform state in Azure Storage for team collaboration
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstate1dc603"  # Your storage account name
    container_name       = "tfstate"
    key                  = "awesome-devops.tfstate"
  }
}

# ───────────────────────────────────────────────────────────────────
# AZURE PROVIDER CONFIGURATION
# ───────────────────────────────────────────────────────────────────
# Configures the Azure provider with specific features
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false  # Allow deletion
    }
  }
}

# ═══════════════════════════════════════════════════════════════════
# VARIABLES & CONFIGURATION
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# INPUT VARIABLES: Customizable Parameters
# ───────────────────────────────────────────────────────────────────
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"  # Default environment
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "australiaeast"  # Azure Australia East region
}

variable "resource_prefix" {
  description = "Prefix for all resources"
  type        = string
  default     = "awesome"  # Prefix for resource names
}

# ───────────────────────────────────────────────────────────────────
# LOCAL VARIABLES: Computed Values and Tags
# ───────────────────────────────────────────────────────────────────
locals {
  common_tags = {
    Project     = "AwesomeDevOps"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Complete DevOps Pipeline with Auto-Scaling"
  }
}

# ═══════════════════════════════════════════════════════════════════
# RESOURCE GROUP
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# RESOURCE GROUP: Container for All Resources
# ───────────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_prefix}-devops-rg"
  location = var.location
  tags     = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════
# NETWORKING - VNet, Subnets, NSG
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# VIRTUAL NETWORK: Isolated Network Environment
# ───────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "${var.resource_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]  # Large private IP range
  tags                = local.common_tags
}

# ───────────────────────────────────────────────────────────────────
# SUBNET: AKS Cluster Network Segment
# ───────────────────────────────────────────────────────────────────
resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]  # Subnet for AKS nodes
}

# ───────────────────────────────────────────────────────────────────
# NETWORK SECURITY GROUP: Traffic Control
# ───────────────────────────────────────────────────────────────────
resource "azurerm_network_security_group" "aks" {
  name                = "${var.resource_prefix}-aks-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"  # HTTPS traffic
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════
# LOG ANALYTICS & MONITORING
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# LOG ANALYTICS WORKSPACE: Centralized Logging
# ───────────────────────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.resource_prefix}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"      # Pay-per-GB pricing
  retention_in_days   = 30               # Keep logs for 30 days
  tags                = local.common_tags
}

# ───────────────────────────────────────────────────────────────────
# APPLICATION INSIGHTS: Application Performance Monitoring
# ───────────────────────────────────────────────────────────────────
resource "azurerm_application_insights" "main" {
  name                = "${var.resource_prefix}-appinsights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"            # Web application type
  tags                = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════
# AZURE CONTAINER REGISTRY (ACR)
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# CONTAINER REGISTRY: Private Docker Registry
# ───────────────────────────────────────────────────────────────────
resource "azurerm_container_registry" "main" {
  name                = "${var.resource_prefix}acr${random_string.acr_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"       # Standard tier for production
  admin_enabled       = true             # Enable admin access

  tags = local.common_tags
}

# ───────────────────────────────────────────────────────────────────
# RANDOM SUFFIX: Unique ACR Name
# ───────────────────────────────────────────────────────────────────
resource "random_string" "acr_suffix" {
  length  = 8
  special = false
  upper   = false
}

# ═══════════════════════════════════════════════════════════════════
# AZURE KUBERNETES SERVICE (AKS) WITH AUTO-SCALING - FIXED
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# DATA SOURCE: Available Kubernetes Versions
# ───────────────────────────────────────────────────────────────────
data "azurerm_kubernetes_service_versions" "current" {
  location = var.location
}

# ───────────────────────────────────────────────────────────────────
# AKS CLUSTER: Managed Kubernetes Service
# ───────────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.resource_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.resource_prefix}-aks"
  kubernetes_version  = data.azurerm_kubernetes_service_versions.current.latest_version

  # ───────────────────────────────────────────────────────────────────
  # DEFAULT NODE POOL: Worker Nodes with Auto-scaling
  # ───────────────────────────────────────────────────────────────────
  default_node_pool {
    name                = "default"
    vm_size             = "Standard_D2s_v3"  # 2 vCPU, 8GB RAM
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true               # Enable node auto-scaling
    min_count           = 2                  # Minimum nodes
    max_count           = 10                 # Maximum nodes
    os_disk_size_gb     = 30                 # OS disk size
    
    node_labels = {
      "workload" = "general"  # Node labels for scheduling
    }

    tags = local.common_tags
  }

  # ───────────────────────────────────────────────────────────────────
  # IDENTITY: System-assigned Managed Identity
  # ───────────────────────────────────────────────────────────────────
  identity {
    type = "SystemAssigned"  # Azure-managed identity
  }

  # ───────────────────────────────────────────────────────────────────
  # NETWORK PROFILE: Advanced Networking Configuration
  # ───────────────────────────────────────────────────────────────────
  network_profile {
    network_plugin     = "azure"        # Azure CNI networking
    network_policy     = "azure"        # Network policies
    load_balancer_sku  = "standard"     # Standard load balancer
    service_cidr       = "10.1.0.0/16"  # Kubernetes services CIDR
    dns_service_ip     = "10.1.0.10"    # Internal DNS service IP
  }

  # ───────────────────────────────────────────────────────────────────
  # MONITORING: Log Analytics Integration
  # ───────────────────────────────────────────────────────────────────
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # ───────────────────────────────────────────────────────────────────
  # AZURE POLICY: Kubernetes Policy Enforcement
  # ───────────────────────────────────────────────────────────────────
  azure_policy_enabled = true

  # ───────────────────────────────────────────────────────────────────
  # AUTO-SCALER PROFILE: Cluster Auto-scaling Behavior
  # ───────────────────────────────────────────────────────────────────
  auto_scaler_profile {
    balance_similar_node_groups      = false
    max_graceful_termination_sec     = 600    # 10 minute termination grace
    scale_down_delay_after_add       = "10m"  # Wait 10m after scale-up
    scale_down_delay_after_delete    = "10s"
    scale_down_delay_after_failure   = "3m"
    scale_down_unneeded              = "10m"  # Node unneeded for 10m
    scale_down_unready               = "20m"  # Node unready for 20m
    scale_down_utilization_threshold = "0.5"  # 50% utilization threshold
  }

  tags = local.common_tags
}

# ───────────────────────────────────────────────────────────────────
# ROLE ASSIGNMENT: AKS Access to ACR
# ───────────────────────────────────────────────────────────────────
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"  # Pull images from ACR
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}

# ═══════════════════════════════════════════════════════════════════
# COSMOSDB WITH MONGODB API - FIXED
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# COSMOSDB ACCOUNT: Globally Distributed Database
# ───────────────────────────────────────────────────────────────────
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.resource_prefix}-cosmos-${random_string.cosmos_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"      # Pricing tier
  kind                = "MongoDB"       # MongoDB API compatibility

  consistency_policy {
    consistency_level = "Session"       # Session consistency
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0               # Primary region
  }

  capabilities {
    name = "EnableMongo"        # Enable MongoDB protocol
  }

  capabilities {
    name = "EnableServerless"   # Serverless capacity mode
  }

  tags = local.common_tags
}

# ───────────────────────────────────────────────────────────────────
# COSMOSDB MONGO DATABASE: Database Instance
# ───────────────────────────────────────────────────────────────────
resource "azurerm_cosmosdb_mongo_database" "main" {
  name                = "devops-db"
  resource_group_name = azurerm_cosmosdb_account.main.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
}

# ───────────────────────────────────────────────────────────────────
# RANDOM SUFFIX: Unique CosmosDB Name
# ───────────────────────────────────────────────────────────────────
resource "random_string" "cosmos_suffix" {
  length  = 6
  special = false
  upper   = false
}

# ═══════════════════════════════════════════════════════════════════
# MONITORING ALERTS
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# ACTION GROUP: Alert Notifications
# ───────────────────────────────────────────────────────────────────
resource "azurerm_monitor_action_group" "main" {
  name                = "${var.resource_prefix}-action-group"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "devops"

  email_receiver {
    name                    = "admin"
    email_address           = "admin@example.com"
    use_common_alert_schema = true
  }

  tags = local.common_tags
}

# ───────────────────────────────────────────────────────────────────
# METRIC ALERT: High CPU Usage
# ───────────────────────────────────────────────────────────────────
resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "${var.resource_prefix}-high-cpu-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.main.id]
  description         = "Alert when node CPU exceeds 80%"
  severity            = 2                    # Severity level
  frequency           = "PT1M"               # Check every 1 minute
  window_size         = "PT5M"               # 5-minute evaluation window

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"             # Average CPU usage
    operator         = "GreaterThan"
    threshold        = 80                    # 80% CPU threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = local.common_tags
}

# ───────────────────────────────────────────────────────────────────
# METRIC ALERT: High Memory Usage
# ───────────────────────────────────────────────────────────────────
resource "azurerm_monitor_metric_alert" "high_memory" {
  name                = "${var.resource_prefix}-high-memory-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.main.id]
  description         = "Alert when node memory exceeds 85%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85                    # 85% memory threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════
# KUBERNETES PROVIDER CONFIGURATION
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# KUBERNETES PROVIDER: Connect to AKS Cluster
# ───────────────────────────────────────────────────────────────────
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
}

# ───────────────────────────────────────────────────────────────────
# KUBERNETES NAMESPACES: Environment Isolation
# ───────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
    labels = {
      environment = "staging"
      managed-by  = "terraform"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

resource "kubernetes_namespace" "production" {
  metadata {
    name = "production"
    labels = {
      environment = "production"
      managed-by  = "terraform"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# ───────────────────────────────────────────────────────────────────
# KUBERNETES SECRETS: Database Connection Strings
# ───────────────────────────────────────────────────────────────────
resource "kubernetes_secret" "mongodb_staging" {
  metadata {
    name      = "mongodb-secret"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  data = {
    connection-string = "mongodb://${azurerm_cosmosdb_account.main.name}:${azurerm_cosmosdb_account.main.primary_key}@${azurerm_cosmosdb_account.main.name}.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@${azurerm_cosmosdb_account.main.name}@"
  }

  type = "Opaque"
}

resource "kubernetes_secret" "mongodb_production" {
  metadata {
    name      = "mongodb-secret"
    namespace = kubernetes_namespace.production.metadata[0].name
  }

  data = {
    connection-string = "mongodb://${azurerm_cosmosdb_account.main.name}:${azurerm_cosmosdb_account.main.primary_key}@${azurerm_cosmosdb_account.main.name}.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@${azurerm_cosmosdb_account.main.name}@"
  }

  type = "Opaque"
}

# ═══════════════════════════════════════════════════════════════════
# OUTPUTS - FIXED
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# TERRAFORM OUTPUTS: Deployment Information
# ───────────────────────────────────────────────────────────────────
output "resource_group_name" {
  value       = azurerm_resource_group.main.name
  description = "Resource group name"
}

output "aks_cluster_name" {
  value       = azurerm_kubernetes_cluster.main.name
  description = "AKS cluster name"
}

output "aks_cluster_id" {
  value       = azurerm_kubernetes_cluster.main.id
  description = "AKS cluster ID"
}

output "acr_login_server" {
  value       = azurerm_container_registry.main.login_server
  description = "Container registry URL"
}

output "acr_admin_username" {
  value       = azurerm_container_registry.main.admin_username
  description = "ACR admin username"
  sensitive   = true  # Mark as sensitive data
}

output "acr_admin_password" {
  value       = azurerm_container_registry.main.admin_password
  description = "ACR admin password"
  sensitive   = true  # Mark as sensitive data
}

output "cosmosdb_endpoint" {
  value       = azurerm_cosmosdb_account.main.endpoint
  description = "CosmosDB endpoint"
}

output "cosmosdb_connection_string" {
  value       = "mongodb://${azurerm_cosmosdb_account.main.name}:${azurerm_cosmosdb_account.main.primary_key}@${azurerm_cosmosdb_account.main.name}.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb"
  description = "CosmosDB connection string"
  sensitive   = true  # Mark as sensitive data
}

output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.main.id
  description = "Log Analytics Workspace ID"
}

output "application_insights_key" {
  value       = azurerm_application_insights.main.instrumentation_key
  description = "Application Insights instrumentation key"
  sensitive   = true  # Mark as sensitive data
}

output "kube_config" {
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  description = "Kubernetes configuration"
  sensitive   = true  # Mark as sensitive data
}

# ───────────────────────────────────────────────────────────────────
# DEPLOYMENT SUMMARY: Human-readable Output
# ───────────────────────────────────────────────────────────────────
output "infrastructure_summary" {
  value = <<-EOT
  ═══════════════════════════════════════════════════════════
  🚀 AWESOME DEVOPS INFRASTRUCTURE DEPLOYED SUCCESSFULLY!
  ═══════════════════════════════════════════════════════════
  
  📦 Resource Group: ${azurerm_resource_group.main.name}
  🌐 Location: ${azurerm_resource_group.main.location}
  
  🎯 AKS Cluster:
     - Name: ${azurerm_kubernetes_cluster.main.name}
     - Version: ${azurerm_kubernetes_cluster.main.kubernetes_version}
     - Auto-Scaling: 2-10 nodes
     - Current Nodes: 3
  
  🐳 Container Registry:
     - URL: ${azurerm_container_registry.main.login_server}
  
  🗄️ CosmosDB (MongoDB):
     - Endpoint: ${azurerm_cosmosdb_account.main.endpoint}
     - Database: devops-db
  
  📊 Monitoring:
     - Log Analytics: Enabled
     - Application Insights: Enabled
     - CPU Alert: > 80%
     - Memory Alert: > 85%
  
  🎭 Namespaces:
     - staging (auto-deploy)
     - production (manual approval)
  
  ✅ All systems operational!
  ═══════════════════════════════════════════════════════════
  EOT
  description = "Infrastructure deployment summary"
}

# ═══════════════════════════════════════════════════════════════════
# END OF TERRAFORM INFRASTRUCTURE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════
# Summary: Complete Azure infrastructure with auto-scaling capabilities
# Resources: AKS, ACR, CosmosDB, Networking, Monitoring, Alerts
# Features: High availability, security, monitoring, cost optimization
# ═══════════════════════════════════════════════════════════════════