package main

import (
	"fmt"

	"turnkey/pulumi/aks"
	"turnkey/pulumi/bootstrap"
	"turnkey/pulumi/doks"

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

		ctx.Export("clusterName", pulumi.String(clusterName))
		ctx.Export("provider", pulumi.String(provider))
		return nil
	})
}
