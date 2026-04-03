package main

import (
	"encoding/json"
	"fmt"

	"turnkey/pulumi/aks"
	"turnkey/pulumi/bootstrap"
	"turnkey/pulumi/doks"

	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "")

		provider := cfg.Require("cluster.provider")
		clusterName := cfg.Require("cluster.name")
		repoURL := cfg.Require("argocd.repoUrl")
		targetRevision := cfg.Require("argocd.targetRevision")
		rootPath := cfg.Get("argocd.path")
		if rootPath == "" {
			rootPath = "bootstrap"
		}

		var kubeconfig pulumi.StringOutput
		switch provider {
		case "aks":
			kc, err := aks.Provision(ctx, cfg)
			if err != nil {
				return err
			}
			kubeconfig = kc
		case "doks":
			kc, err := doks.Provision(ctx, cfg)
			if err != nil {
				return err
			}
			kubeconfig = kc
		default:
			return fmt.Errorf("unsupported cluster.provider %q (must be aks or doks)", provider)
		}

		k8sProvider, err := bootstrap.NewProvider(ctx, kubeconfig)
		if err != nil {
			return err
		}

		argocdRelease, err := bootstrap.InstallArgoCD(ctx, k8sProvider)
		if err != nil {
			return err
		}

		if err := bootstrap.ApplyRootApplication(ctx, k8sProvider, argocdRelease, repoURL, targetRevision, rootPath); err != nil {
			return err
		}

		// Apply any additional applications configured
		if err := applyAdditionalApps(ctx, k8sProvider, argocdRelease, cfg); err != nil {
			return err
		}

		ctx.Export("clusterName", pulumi.String(clusterName))
		ctx.Export("provider", pulumi.String(provider))
		// Lets CI and scripts run kubectl waits after `pulumi up` without manual kubeconfig plumbing.
		ctx.Export("kubeconfig", pulumi.ToSecret(kubeconfig))
		return nil
	})
}

// applyAdditionalApps loads and applies additional ArgoCD Applications from Pulumi config
func applyAdditionalApps(ctx *pulumi.Context, k8sProvider *kubernetes.Provider, argocdRelease pulumi.Resource, cfg *config.Config) error {
	// Check if additional apps are configured
	additionalAppsJSON := cfg.Get("additionalApps")
	if additionalAppsJSON == "" {
		return nil // No additional apps configured
	}

	var additionalApps []bootstrap.AdditionalAppConfig
	if err := json.Unmarshal([]byte(additionalAppsJSON), &additionalApps); err != nil {
		return fmt.Errorf("failed to parse additionalApps config: %w", err)
	}

	if len(additionalApps) == 0 {
		return nil
	}

	ctx.Log.Info(fmt.Sprintf("Applying %d additional ArgoCD applications", len(additionalApps)), nil)

	if err := bootstrap.ApplyAdditionalApplications(ctx, k8sProvider, argocdRelease, additionalApps); err != nil {
		return fmt.Errorf("failed to apply additional applications: %w", err)
	}

	return nil
}
