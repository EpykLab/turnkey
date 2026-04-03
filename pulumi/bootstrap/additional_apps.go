package bootstrap

import (
	"fmt"

	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/apiextensions"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// AdditionalAppConfig represents an additional application to deploy via ArgoCD
type AdditionalAppConfig struct {
	Name           string                 `json:"name"`                 // Application name (e.g., "home-pipelines")
	RepoURL        string                 `json:"repoURL"`              // Git repo or OCI registry URL
	Chart          string                 `json:"chart"`                // Chart name (for Helm) or path (for Git)
	TargetRevision string                 `json:"targetRevision"`       // Git branch/tag or chart version
	Path           string                 `json:"path,omitempty"`       // Path within repo (for Git sources)
	Namespace      string                 `json:"namespace"`            // Target namespace
	IsHelm         bool                   `json:"isHelm"`               // true for Helm chart, false for plain manifests
	ValueFiles     []string               `json:"valueFiles,omitempty"` // Helm value files to use
	HelmValues     map[string]interface{} `json:"helmValues,omitempty"` // Inline Helm values
	SyncWave       string                 `json:"syncWave,omitempty"`   // ArgoCD sync wave annotation
	Project        string                 `json:"project,omitempty"`    // ArgoCD project (default: "default")
}

// ApplyAdditionalApplications creates ArgoCD Applications for extra charts specified in config
func ApplyAdditionalApplications(ctx *pulumi.Context, k8s *kubernetes.Provider, argocdRelease pulumi.Resource, apps []AdditionalAppConfig) error {
	for _, app := range apps {
		if err := applyAdditionalApplication(ctx, k8s, argocdRelease, app); err != nil {
			return fmt.Errorf("failed to apply additional app %s: %w", app.Name, err)
		}
	}
	return nil
}

func applyAdditionalApplication(ctx *pulumi.Context, k8s *kubernetes.Provider, argocdRelease pulumi.Resource, app AdditionalAppConfig) error {
	// Set defaults
	if app.Project == "" {
		app.Project = "default"
	}
	if app.SyncWave == "" {
		app.SyncWave = "50" // Default middle wave, after platform (30) but before status page (100)
	}

	// Build source spec
	source := map[string]interface{}{
		"repoURL":        app.RepoURL,
		"targetRevision": app.TargetRevision,
	}

	if app.IsHelm {
		source["chart"] = app.Chart
		helmSpec := map[string]interface{}{
			"releaseName": app.Name,
		}
		if len(app.ValueFiles) > 0 {
			helmSpec["valueFiles"] = app.ValueFiles
		}
		if len(app.HelmValues) > 0 {
			helmSpec["valuesObject"] = app.HelmValues
		}
		source["helm"] = helmSpec
	} else {
		source["path"] = app.Path
		if app.Path == "" {
			source["path"] = "."
		}
	}

	// Create the Application
	_, err := apiextensions.NewCustomResource(ctx, fmt.Sprintf("additional-app-%s", app.Name), &apiextensions.CustomResourceArgs{
		ApiVersion: pulumi.String("argoproj.io/v1alpha1"),
		Kind:       pulumi.String("Application"),
		Metadata: &metav1.ObjectMetaArgs{
			Name:      pulumi.String(app.Name),
			Namespace: pulumi.String("argocd"),
			Annotations: pulumi.StringMap{
				"argocd.argoproj.io/sync-wave": pulumi.String(app.SyncWave),
			},
		},
		OtherFields: kubernetes.UntypedArgs{
			"spec": map[string]interface{}{
				"project": app.Project,
				"source":  source,
				"destination": map[string]interface{}{
					"server":    "https://kubernetes.default.svc",
					"namespace": app.Namespace,
				},
				"syncPolicy": map[string]interface{}{
					"automated": map[string]interface{}{
						"prune":    true,
						"selfHeal": true,
					},
					"syncOptions": []string{"CreateNamespace=true"},
					"retry": map[string]interface{}{
						"limit": 15,
						"backoff": map[string]interface{}{
							"duration":    "10s",
							"factor":      2,
							"maxDuration": "5m",
						},
					},
				},
			},
		},
	}, pulumi.Provider(k8s), pulumi.DependsOn([]pulumi.Resource{argocdRelease}))

	return err
}
