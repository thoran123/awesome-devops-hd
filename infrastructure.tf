# ═══════════════════════════════════════════════════════════════════
# COMPLETE AZURE INFRASTRUCTURE AS CODE - UPDATED
# ═══════════════════════════════════════════════════════════════════
# Fixed for current Azure provider version
# ═══════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
  
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatedevops"  # Use your storage account name
    container_name       = "tfstate"
    key                  = "awesome-devops.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ═══════════════════════════════════════════════════════════════════
# VARIABLES & CONFIGURATION
# ═══════════════════════════════════════════════════════════════════

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "australiaeast"
}

variable "resource_prefix" {
  description = "Prefix for all resources"
  type        = string
  default     = "awesome"
}

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

resource "azurerm_resource_group" "main" {
  name     = "${var.resource_prefix}-devops-rg"
  location = var.location
  tags     = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════
# NETWORKING - VNet, Subnets, NSG
# ═══════════════════════════════════════════════════════════════════

resource "azurerm_virtual_network" "main" {
  name                = "${var.resource_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

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
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════
# LOG ANALYTICS & MONITORING
# ═══════════════════════════════════════════════════════════════════

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.resource_prefix}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_application_insights" "main" {
  name                = "${var.resource_prefix}-appinsights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════
# AZURE CONTAINER REGISTRY (ACR)
# ═══════════════════════════════════════════════════════════════════

resource "azurerm_container_registry" "main" {
  name                = "${var.resource_prefix}acr${random_string.acr_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  admin_enabled       = true

  tags = local.common_tags
}

resource "random_string" "acr_suffix" {
  length  = 8
  special = false
  upper   = false
}

# ═══════════════════════════════════════════════════════════════════
# AZURE KUBERNETES SERVICE (AKS) WITH AUTO-SCALING - FIXED
# ═══════════════════════════════════════════════════════════════════

# Get available Kubernetes versions
data "azurerm_kubernetes_service_versions" "current" {
  location = var.location
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.resource_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.resource_prefix}-aks"
  kubernetes_version  = data.azurerm_kubernetes_service_versions.current.latest_version

  # Default node pool with AUTOSCALING
  default_node_pool {
    name                = "default"
    vm_size             = "Standard_D2s_v3"
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 10
    node_count          = 3
    os_disk_size_gb     = 30
    
    # Node labels for workload optimization
    node_labels = {
      "workload" = "general"
    }

    tags = local.common_tags
  }

  # System-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Network profile for advanced networking - FIXED
  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    load_balancer_sku  = "standard"
    service_cidr       = "10.1.0.0/16"
    dns_service_ip     = "10.1.0.10"
    # Removed deprecated docker_bridge_cidr
  }

  # Enable monitoring with Log Analytics
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Enable Azure Policy
  azure_policy_enabled = true

  # Auto-scaler profile
  auto_scaler_profile {
    balance_similar_node_groups      = false
    max_graceful_termination_sec     = 600
    scale_down_delay_after_add       = "10m"
    scale_down_delay_after_delete    = "10s"
    scale_down_delay_after_failure   = "3m"
    scale_down_unneeded              = "10m"
    scale_down_unready               = "20m"
    scale_down_utilization_threshold = "0.5"
  }

  tags = local.common_tags
}

# Grant AKS access to ACR
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}

# ═══════════════════════════════════════════════════════════════════
# COSMOSDB WITH MONGODB API - FIXED
# ═══════════════════════════════════════════════════════════════════

resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.resource_prefix}-cosmos-${random_string.cosmos_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "MongoDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableMongo"
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = local.common_tags
}

resource "azurerm_cosmosdb_mongo_database" "main" {
  name                = "devops-db"
  resource_group_name = azurerm_cosmosdb_account.main.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "random_string" "cosmos_suffix" {
  length  = 6
  special = false
  upper   = false
}

# ═══════════════════════════════════════════════════════════════════
# MONITORING ALERTS
# ═══════════════════════════════════════════════════════════════════

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

# Alert for high CPU usage
resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "${var.resource_prefix}-high-cpu-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.main.id]
  description         = "Alert when node CPU exceeds 80%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = local.common_tags
}

# Alert for high memory usage
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
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════
# KUBERNETES PROVIDER CONFIGURATION
# ═══════════════════════════════════════════════════════════════════

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
}

# Create namespaces
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

# Create secrets for MongoDB connection - FIXED
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
  sensitive   = true
}

output "acr_admin_password" {
  value       = azurerm_container_registry.main.admin_password
  description = "ACR admin password"
  sensitive   = true
}

output "cosmosdb_endpoint" {
  value       = azurerm_cosmosdb_account.main.endpoint
  description = "CosmosDB endpoint"
}

output "cosmosdb_connection_string" {
  value       = "mongodb://${azurerm_cosmosdb_account.main.name}:${azurerm_cosmosdb_account.main.primary_key}@${azurerm_cosmosdb_account.main.name}.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb"
  description = "CosmosDB connection string"
  sensitive   = true
}

output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.main.id
  description = "Log Analytics Workspace ID"
}

output "application_insights_key" {
  value       = azurerm_application_insights.main.instrumentation_key
  description = "Application Insights instrumentation key"
  sensitive   = true
}

output "kube_config" {
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  description = "Kubernetes configuration"
  sensitive   = true
}

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