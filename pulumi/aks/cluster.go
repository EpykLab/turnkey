package aks

import (
	"encoding/base64"
	"fmt"
	"strconv"

	containerservice "github.com/pulumi/pulumi-azure-native-sdk/containerservice/v2"
	"github.com/pulumi/pulumi-azure-native-sdk/resources/v2"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Provision returns the cluster kubeconfig for AKS environments.
func Provision(ctx *pulumi.Context, cfg *config.Config) (pulumi.StringOutput, error) {
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
		return provisionManaged(ctx, cfg)
	default:
		return pulumi.String("").ToStringOutput(), fmt.Errorf("unsupported cluster.provisionMode %q (must be existing or managed)", mode)
	}
}

func provisionManaged(ctx *pulumi.Context, cfg *config.Config) (pulumi.StringOutput, error) {
	clusterName := cfg.Require("cluster.name")
	location := cfg.Require("cluster.region")
	nodeSize := cfg.Require("cluster.nodeSize")

	nodeCount := 1
	if configured := cfg.Get("cluster.nodeCount"); configured != "" {
		parsed, err := strconv.Atoi(configured)
		if err != nil {
			return pulumi.String("").ToStringOutput(), err
		}
		nodeCount = parsed
	}

	rgName := "rg-" + clusterName

	rg, err := resources.NewResourceGroup(ctx, "turnkey-aks-rg", &resources.ResourceGroupArgs{
		ResourceGroupName: pulumi.String(rgName),
		Location:          pulumi.String(location),
	})
	if err != nil {
		return pulumi.String("").ToStringOutput(), err
	}

	clusterArgs := &containerservice.ManagedClusterArgs{
		ResourceGroupName: rg.Name,
		ResourceName:      pulumi.String(clusterName),
		Location:          pulumi.String(location),
		DnsPrefix:         pulumi.String(clusterName),
		Identity: &containerservice.ManagedClusterIdentityArgs{
			Type: containerservice.ResourceIdentityTypeSystemAssigned,
		},
		AgentPoolProfiles: containerservice.ManagedClusterAgentPoolProfileArray{
			&containerservice.ManagedClusterAgentPoolProfileArgs{
				Name:   pulumi.String("default"),
				Count:  pulumi.Int(nodeCount),
				VmSize: pulumi.String(nodeSize),
				Mode:   containerservice.AgentPoolModeSystem,
				OsType: containerservice.OSTypeLinux,
			},
		},
	}

	if version := cfg.Get("cluster.version"); version != "" {
		clusterArgs.KubernetesVersion = pulumi.String(version)
	}

	cluster, err := containerservice.NewManagedCluster(ctx, "turnkey-aks-cluster", clusterArgs)
	if err != nil {
		return pulumi.String("").ToStringOutput(), err
	}

	creds := containerservice.ListManagedClusterUserCredentialsOutput(ctx,
		containerservice.ListManagedClusterUserCredentialsOutputArgs{
			ResourceGroupName: rg.Name,
			ResourceName:      cluster.Name,
		},
		pulumi.DependsOn([]pulumi.Resource{cluster}),
	)

	kubeconfig := creds.Kubeconfigs().Index(pulumi.Int(0)).Value().ApplyT(func(v string) (string, error) {
		decoded, err := base64.StdEncoding.DecodeString(v)
		if err != nil {
			return "", fmt.Errorf("failed to decode kubeconfig: %w", err)
		}
		return string(decoded), nil
	}).(pulumi.StringOutput)

	return kubeconfig, nil
}
