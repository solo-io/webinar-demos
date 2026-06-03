here we manage agent in a k8s env 

kind create cluster --name agentregistry


kubectl config get-contexts

install agent registry helm 

helm upgrade -i agentregistry oci://ghcr.io/agentregistry-dev/agentregistry/charts/agentregistry \
    --namespace agentregistry \
    --create-namespace \
    --set config.jwtPrivateKey=$(openssl rand -hex 32) \
    --set image.tag=v0.3.3 \
    --set database.host=postgres-pgvector.agentregistry.svc.cluster.local \
    --set database.password=agentregistry \
    --set database.sslMode=disable

kubectl -n agentregistry port-forward svc/agentregistry 12121:12121

install kagent oss


export OPENAI_API_KEY="your-api-key-here"

helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
    --namespace kagent \
    --create-namespace

helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
    --namespace kagent \
    --set providers.default=openAI \
    --set providers.openAI.apiKey=$OPENAI_API_KEY

kubectl port-forward -n kagent svc/kagent-ui 8080:8080


build the agent 

arctl agent init adk python myagent --model-provider openai --model-name gpt-5.4


File	Description
agent.yaml	The agent definition. This definition holds the registry location and version tag that you want to use when building and pushing the image to your registry. It also adds the MCP server references that you added to the agent.
docker-compose.yaml	A Docker compose file that is used to spin up and run your agent when you use the arctl agent run command.
Dockerfile	The Dockerfile to spin up and run your agent in a containerized environment.
myagent	A directory that includes the agent.py script that defines the agent, including the provider and model that you want to use. The directory also includes the agent card for agent discovery.
pyproject.toml	The dependency definition of your agent.
README.md	An introduction to the agent that you created with instructions for how to further customize it.


arctl agent run myagent

#Publish the agent image 

arctl agent build myagent

arctl agent publish myagent

arctl agent list

arctl deployments create myagent \
 --type agent \
 --provider-id kubernetes-default \
 --namespace kagent

kubectl get pods | grep myagent


kubectl get agent -o yaml
