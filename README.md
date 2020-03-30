    ############################
    mkdir metallb-hcp
    cd metallb-hcp/
    cat config.yaml
    apiVersion: v1
    kind: ConfigMap
    metadata:
      namespace: metallb-system
      name: config
    data:
      config: |
        address-pools:
        - name: default
          protocol: layer2
          addresses:
          - 192.168.1.180-192.168.1.199

    kubectl apply -f https://raw.githubusercontent.com/google/metallb/v0.9.3/manifests/namespace.yaml
    kubectl apply -f https://raw.githubusercontent.com/google/metallb/v0.9.3/manifests/metallb.yaml
    kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
    
    k get -n metallb-system all
    k get -n metallb-system configmaps
    k apply -f config.yaml
    k get -n metallb-system configmaps
    k describe -n metallb-system configmaps config
    
    
    ############################
    git clone https://github.com/jear/kubernetes-local-cluster-flannel-metallb-traefik.git
    
    
    kubectl create namespace traefik
    
    cd kubernetes-local-cluster-flannel-metallb-traefik
    kubectl apply -f traefik/traefik-rbac.yaml
    kubectl apply -f traefik/traefik-definition.yaml
    kubectl apply -f traefik/traefik-deployment.yaml
    
    
    # Add DNS entry with traefik loadbalancer EXTERNAL-IP 
    k get svc -n traefik
    NAME                TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)        AGE
    traefik             LoadBalancer   10.96.28.89    192.168.1.180   80:32500/TCP   6m54s
    traefik-dashboard   ClusterIP      10.96.31.147   <none>          8080/TCP       6m53s
        
        
        
    cat traefik/traefik-ingress-dashboard.yaml
    ---
    apiVersion: traefik.containo.us/v1alpha1
    kind: IngressRoute
    metadata:
      name: traefik-dashboard-ingress
      namespace: traefik
    spec:
      entryPoints:
    - web
      routes:
      - match: Host(`traefik-hcp.jear.co`)
        kind: Rule
        services:
        - name: traefik-dashboard
          port: 8080
    
    

    kubectl apply -f traefik/traefik-ingress-dashboard.yaml
