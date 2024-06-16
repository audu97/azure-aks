terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.107.0"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.30.0"
    }

    helm = {
      source = "hashicorp/helm"
      version = "2.13.2"
    }
  }
}

provider "azurerm" {
  # Configuration options
  features {}
}


resource "azurerm_resource_group" "aks-resource" {
  name     = "aks-resources"
  location = "France Central"
}

resource "azurerm_kubernetes_cluster" "test_cluster" {
  name                = "example-aks1"
  location            = azurerm_resource_group.aks-resource.location
  resource_group_name = azurerm_resource_group.aks-resource.name
  dns_prefix          = "testaks"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_D2_v2"
  }


  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}

data "azurerm_kubernetes_cluster" "test_cluster" {
  name = azurerm_kubernetes_cluster.test_cluster.name
  resource_group_name = azurerm_resource_group.aks-resource.name
}

resource "local_file" "kubeconfig" {
  content = data.azurerm_kubernetes_cluster.test_cluster.kube_config_raw
  filename = "/home/ephraim/.kube/config"
  
}

resource "null_resource" "wait_for_kubeconfig" {
  provisioner "local-exec" {
    command = "sleep 10"

  }

  depends_on = [ local_file.kubeconfig ]
  
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "helm" {
    kubernetes {
      config_path = local_file.kubeconfig.filename
    }
}


resource "kubernetes_namespace" "test_namespace" {
  metadata{
    name = "monitoring"
  }

  depends_on = [ local_file.kubeconfig ]
}


resource "helm_release" "prom-helm" {
    name = "prometheus"
    repository = "https://prometheus-community.github.io/helm-charts"
    chart      = "prometheus"
    namespace  = kubernetes_namespace.test_namespace.metadata[0].name
    depends_on = [ kubernetes_namespace.test_namespace ]
}

resource "helm_release" "graf-helm" {
    name = "grafana"
    repository = "https://grafana.github.io/helm-charts"
    chart      = "grafana"
    namespace  = kubernetes_namespace.test_namespace.metadata[0].name
    depends_on = [ kubernetes_namespace.test_namespace ]
  
}

resource "kubernetes_deployment" "nginx_depl" {
    metadata {
      name = "nginx-deployment"
      namespace = kubernetes_namespace.test_namespace.metadata[0].name
    }
    spec {
      replicas = 2

      selector {
        match_labels = {
            app = "nginx"
        }
      }

      template {
        metadata {
          labels = {
            app = "nginx"
          }
        }

        spec {
          container {
            name = "nginx"
            image = "nginx:latest"

            port {
              container_port = 80
            }
          }
        }
      }
    }
    depends_on = [ kubernetes_namespace.test_namespace ]
}


resource "kubernetes_service" "nginx-service" {
    metadata {
      name = "nginx-service"
      namespace = kubernetes_namespace.test_namespace.metadata[0].name
    }

    spec {
      selector = {
        app = "nginx"
      }

      port {
        port = 80
        target_port = 80
      }

      type = "LoadBalancer"
    }
    depends_on = [ kubernetes_namespace.test_namespace]
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.test_cluster.kube_config[0].client_certificate
  sensitive = true
}

output "kube_config" {
  value = azurerm_kubernetes_cluster.test_cluster.kube_config_raw

  sensitive = true
}