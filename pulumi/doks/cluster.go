package doks

import (
	"fmt"
	"strconv"

	"github.com/pulumi/pulumi-digitalocean/sdk/v4/go/digitalocean"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Provision creates a DOKS cluster and returns kubeconfig.
func Provision(ctx *pulumi.Context, cfg *config.Config) (pulumi.StringOutput, error) {
	mode := cfg.Get("cluster.provisionMode")
	if mode == "" {
		mode = "managed"
	}

	if kubeconfig := cfg.Get("cluster.kubeconfig"); kubeconfig != "" {
		return pulumi.String(kubeconfig).ToStringOutput(), nil
	}

	if mode == "existing" {
		return pulumi.String("").ToStringOutput(), fmt.Errorf("DOKS existing mode requires cluster.kubeconfig")
	}
	if mode != "managed" {
		return pulumi.String("").ToStringOutput(), fmt.Errorf("unsupported cluster.provisionMode %q (must be existing or managed)", mode)
	}

	clusterName := cfg.Require("cluster.name")
	region := cfg.Require("cluster.region")
	version := cfg.Require("cluster.version")
	nodeSize := cfg.Require("cluster.nodeSize")

	nodeCount := 1
	if configured := cfg.Get("cluster.nodeCount"); configured != "" {
		parsed, err := strconv.Atoi(configured)
		if err != nil {
			return pulumi.String("").ToStringOutput(), err
		}
		nodeCount = parsed
	}

	cluster, err := digitalocean.NewKubernetesCluster(ctx, "turnkey-doks-cluster", &digitalocean.KubernetesClusterArgs{
		Name:    pulumi.String(clusterName),
		Region:  pulumi.String(region),
		Version: pulumi.String(version),
		NodePool: &digitalocean.KubernetesClusterNodePoolArgs{
			Name:      pulumi.String("default"),
			Size:      pulumi.String(nodeSize),
			NodeCount: pulumi.Int(nodeCount),
		},
	})
	if err != nil {
		return pulumi.String("").ToStringOutput(), err
	}

	kubeconfig := cluster.KubeConfigs.Index(pulumi.Int(0)).RawConfig().ApplyT(func(v *string) string {
		if v == nil {
			return ""
		}
		return *v
	}).(pulumi.StringOutput)
	return kubeconfig, nil
}
