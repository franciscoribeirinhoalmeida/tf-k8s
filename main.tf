terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace_v1" "apps" {
  metadata {
    name = "apps"
  }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}


//---------------------- Nginx Resources ------------------------------

resource "kubernetes_secret_v1" "nginx_auth" {
  metadata {
    name = "nginx-auth"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  data = {
    ".htpasswd" = file("${path.module}/.htpasswd")
  }
}

resource "kubernetes_config_map_v1" "nginx_config" {
  metadata {
    name = "nginx-config"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  data = {
    "nginx.conf" = <<EOF
    events {}


    http {
        server {
            listen 80;

            location / {
                return 200 "Hello from nginx";
            }

            location /redis/ {
                auth_basic "Restricted Access";
                auth_basic_user_file /etc/nginx/.htpasswd;
                proxy_pass http://redis-commander-service:80/;
            }

            location /netdata/ {
                proxy_pass http://netdata-service.monitoring.svc.cluster.local:19999/;
            }

            location /counter/ {
                proxy_pass http://counter-app-service:5000/;
            }
        }
    }

    EOF
  }
}

resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name = "nginx"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name

    labels = {
      app = "nginx"
    }
  }

  spec {
    replicas = 1
    
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
          image = "nginx:latest"
          name  = "nginx"

          port {
            container_port = 80
          }

          
          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }

          volume_mount {
            name       = "nginx-auth"
            mount_path = "/etc/nginx/.htpasswd"
            sub_path   = ".htpasswd"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }

            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
        
        volume {
          name = "nginx-config"

          config_map {
            name = kubernetes_config_map_v1.nginx_config.metadata[0].name
          }
        }

        volume {
          name = "nginx-auth"

          secret {
            secret_name = kubernetes_secret_v1.nginx_auth.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "nginx" {
  metadata {
    name = "nginx-service"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "NodePort"
  }
}


//---------------------- Redis Resources ------------------------------

resource "kubernetes_secret_v1" "redis" {
  metadata {
    name = "redis-secret"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  data = {
    password = var.redis_password
  }

  type = "Opaque"
}

resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name = "redis"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name

    labels = {
      app = "redis"
    }
  }
  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis"
        }
      }

      spec {
        container {
          image = "redis:latest"
          name  = "redis"

          port {
            container_port = 6379
          }

          volume_mount {
            name       = "redis-storage"
            mount_path = "/data"
          }

          env {
            name = "REDIS_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.redis.metadata[0].name
                key  = "password"
              }
            }
          }

          command = [
            "/bin/sh",
            "-c"
          ]

          args = [
            "redis-server --requirepass \"$REDIS_PASSWORD\""
          ]

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }

            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "redis-storage"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.redis_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name = "redis-service"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  spec {
    selector = {
      app = "redis"
    }

    port {
      port        = 6379
      target_port = 6379
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment_v1" "redis_commander" {
  metadata {
    name = "redis-commander"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
    labels = {
      app = "redis-commander"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "redis-commander"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis-commander"
        }
      }

      spec {
        container {
          name  = "redis-commander"
          image = "rediscommander/redis-commander:latest"

          env {
            name  = "REDIS_HOSTS"
            value = "local:redis-service:6379:0:${var.redis_password}"
          }

          port {
            container_port = 8081
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis_commander" {
  metadata {
    name = "redis-commander-service"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  spec {
    selector = {
      app = "redis-commander"
    }

    port {
      port        = 80
      target_port = 8081
    }

    type = "NodePort"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "redis_data" {
  metadata {
    name = "redis-data"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_ingress_v1" "redis" {
  metadata {
    name      = "redis-ingress"
    namespace = "apps"
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "redis.local"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "redis-commander-service"

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

//---------------------- Counter App Resources ------------------------------

resource "kubernetes_deployment_v1" "counter_app" {
  metadata {
    name      = "counter-app"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "counter-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "counter-app"
        }
      }

      spec {
        container {
          name  = "counter-app"
          image = "ghcr.io/franciscoribeirinhoalmeida/flask-counter:latest"

          image_pull_policy = "Always"

          port {
            container_port = 5000
          }

          env {
            name  = "REDIS_HOST"
            value = kubernetes_service_v1.redis.metadata[0].name
          }

          env {
            name = "REDIS_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.redis.metadata[0].name
                key  = "password"
              }
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }

            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }

            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }

            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "counter_app" {
  metadata {
    name      = "counter-app-service"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  spec {
    selector = {
      app = "counter-app"
    }

    port {
      port        = 5000
      target_port = 5000
    }

    type = "NodePort"
  }
}

resource "kubernetes_ingress_v1" "counter" {
  metadata {
    name      = "counter-ingress"
    namespace = "apps"
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "counter.local"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "counter-app-service"

              port {
                number = 5000
              }
            }
          }
        }
      }
    }
  }
}

//---------------------- Netdata Resources ------------------------------

resource "kubernetes_deployment_v1" "netdata" {
  metadata {
    name = "netdata"
    namespace = "monitoring"
    labels = {
      app = "netdata"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "netdata"
      }
    }

    template {
      metadata {
        labels = {
          app = "netdata"
        }
      }

      spec {
        container {
          name  = "netdata"
          image = "netdata/netdata:latest"

          port {
            container_port = 19999
          }
        }
      }
    }
  }
  
}

resource "kubernetes_service_v1" "netdata" {
  metadata {
    name      = "netdata-service"
    namespace = "monitoring"
  }

  spec {
    selector = {
      app = "netdata"
    }

    port {
      port        = 19999
      target_port = 19999
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "netdata" {
  metadata {
    name      = "netdata-ingress"
    namespace = "monitoring"
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "netdata.local"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "netdata-service"

              port {
                number = 19999
              }
            }
          }
        }
      }
    }
  }
}





