local k8s = import "k8s.libsonnet";

{
  // static-http service serves static files out of /srv/http on charm

  config: k8s.configmap("static-http", data={
    "nginx.conf": |||
      # Basics
      user nginx;
      pid /var/run/nginx.pid;
      events {
          worker_connections  1024;
      }

      http {
        # Server options and timeouts
        sendfile on;
        gzip on;
        keepalive_timeout 65;

        # Logging
        access_log /dev/stdout;
        error_log stderr info;

        # Content types
        include /etc/nginx/mime.types;
        default_type application/octet-stream;

        server {
          listen 80;

          # Serve files from /mnt
          location / {
            root /mnt;
          }

          # Serve premade error pages
          error_page 500 502 503 504 /50x.html;
          location = /50x.html {
            root /usr/share/nginx/html;
          }
        }
      }
    |||,
  }),

  service: k8s.service("static-http", ports={ http: 80 }),

  ingress: k8s.ingress("static-http",
    tls = true,
    class = "nginx-external",
    rules = { "ekime.kim": {} },
  ),

  deployment: k8s.deployment("static-http",
    pod = {
      volumes: [{
        name: "config",
        configMap: { name: "static-http" },
      }],
      containers: [{
        name: "nginx",
        image: "nginx:1.27.0",
        volumeMounts: [
          {
            name: "config",
            subPath: "nginx.conf",
            mountPath: "/etc/nginx/nginx.conf",
          },
          {
            name: "files",
            mountPath: "/mnt",
          }
        ],
      }],
    } + k8s.mixins.host_path("files", "charm", "/srv/http"),
  ) + k8s.mixins.run_one,
}
