package existing

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Provision returns kubeconfig for a cluster that already exists (e.g. kind, minikube, DOKS kubeconfig-only).
// Set turnkey:cluster.kubeconfig as a Pulumi secret, for example:
//
//	pulumi config set --secret turnkey:cluster.kubeconfig -f ~/.kube/config
//	pulumi config set --secret turnkey:cluster.kubeconfig "$(kind get kubeconfig --name turnkey)"
func Provision(_ *pulumi.Context, cfg *config.Config) pulumi.StringOutput {
	return cfg.RequireSecret("cluster.kubeconfig")
}
