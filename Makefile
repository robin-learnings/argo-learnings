DATE = $(shell date +%FT%T%Z)

create_cluster:
	eksctl create cluster -f cluster.yaml

delete_cluster:
	eksctl delete cluster -f cluster.yaml

describe_cluster:
	eksctl utils describe-stacks --region=us-east-2 --cluster=robin-personal-cluster

aws_identity:
	aws sts get-caller-identity

set_context:
	eksctl utils write-kubeconfig --cluster=robin-personal-cluster --set-kubeconfig-context=true

####  Install Ingress Controller ####

enable_iam_sa_provider:
	eksctl utils associate-iam-oidc-provider --cluster=robin-personal-cluster --approve

create_cluster_role:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/rbac-role.yaml

create_iam_policy:
	aws iam create-policy \
		--policy-name AWSLoadBalancerControllerIAMPolicy \
		--policy-document file://k8s/aws-ingress-controller/iam_policy.json

create_service_account:
	eksctl create iamserviceaccount \
      --cluster=robin-personal-cluster \
      --namespace=kube-system \
      --name=aws-load-balancer-controller \
      --attach-policy-arn=arn:aws:iam::617960797257:policy/AWSLoadBalancerControllerIAMPolicy \
      --override-existing-serviceaccounts \
      --approve

deploy_cert_manager:
	kubectl apply \
		--validate=false \
		-f https://github.com/jetstack/cert-manager/releases/download/v1.1.1/cert-manager.yaml

deploy_ingress_controller:
	kubectl apply -f k8s/aws-ingress-controller/v2_2_0_full.yaml

####  Argocd Commands Below ######

argo_install:
	kubectl create namespace argocd
	kustomize build k8s/argocd-install | kubectl apply  -n argocd -f -

argo_port_fwd:
	kubectl port-forward svc/argocd-server -n argocd 8080:443

argo_get_pwd:
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

argo_create_project:
	kustomize build k8s/argocd-app | kubectl apply -f -

argo_delete_project:
	kustomize build k8s/argocd-app | kubectl delete -f -

argo_update_pwd:
	# bcrypt(password)=$2a$10$rRyBsGSHK6.uc8fntPwVIuLVHgsAhAX7TcdrqW/RADU0uh7CaChLa
	kubectl -n argocd patch secret argocd-secret \
	-p '{"stringData": { "admin.password": "$2a$10$rpz/qiEb0epL2Qfsr0V2Re2cKwE0i2B.jr9oyPfSV8fyWpt2Yja/e", "admin.passwordMtime": "$(DATE)"}}'

just_do_it:
	make create_cluster
	make argo_install
	make argo_create_project

# make create_secret namespace=jomo name=jomo-secret key=secret-key value=secret-value
create_secret:
	kubectl --namespace $(namespace) create secret generic $(name) --from-literal=$(key)=$(value) -o yaml --dry-run=client
