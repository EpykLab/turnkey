package aks

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Provision returns the cluster kubeconfig for AKS environments.
func Provision(_ *pulumi.Context, cfg *config.Config) (pulumi.StringOutput, error) {
	mode := cfg.Get("cluster.provisionMode")
	if mode == "" {
		mode = "existing"
	}

	if kubeconfig := cfg.Get("cluster.kubeconfig"); kubeconfig != "" {
		return pulumi.String(kubeconfig).ToStringOutput(), nil
	}

	switch mode {
	case "existing":
		return pulumi.String("").ToStringOutput(), fmt.Errorf("AKS existing mode requires cluster.kubeconfig")
	case "managed":
		return pulumi.String("").ToStringOutput(), fmt.Errorf("AKS managed mode is not yet implemented; provide cluster.kubeconfig or implement Azure provider resources")
	default:
		return pulumi.String("").ToStringOutput(), fmt.Errorf("unsupported cluster.provisionMode %q (must be existing or managed)", mode)
	}
}
