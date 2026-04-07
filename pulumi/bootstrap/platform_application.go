package bootstrap

import (
	"encoding/json"
	"fmt"

	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/apiextensions"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// ApplyPlatformApplication installs the Argo CD Application that syncs chart/ (platform Helm chart).
// Value files are stack-specific (e.g. kind vs DOKS) via turnkey:platform.valueFiles JSON array.
func ApplyPlatformApplication(ctx *pulumi.Context, k8s *kubernetes.Provider, argocdRelease pulumi.Resource, cfg *config.Config, repoURL, targetRevision string) error {
	valueFiles, err := platformValueFiles(cfg)
	if err != nil {
		return err
	}
	ctx.Log.Info(fmt.Sprintf("turnkey-platform Helm valueFiles: %v", valueFiles), nil)

	_, err = apiextensions.NewCustomResource(ctx, "turnkey-platform-app", &apiextensions.CustomResourceArgs{
		ApiVersion: pulumi.String("argoproj.io/v1alpha1"),
		Kind:       pulumi.String("Application"),
		Metadata: &metav1.ObjectMetaArgs{
			Name:      pulumi.String("turnkey-platform"),
			Namespace: pulumi.String("argocd"),
			Labels: pulumi.StringMap{
				"app.kubernetes.io/managed-by": pulumi.String("pulumi-turnkey"),
			},
		},
		OtherFields: kubernetes.UntypedArgs{
			"spec": map[string]interface{}{
				"project": "default",
				"source": map[string]interface{}{
					"repoURL":        repoURL,
					"targetRevision": targetRevision,
					"path":           "chart",
					"helm": map[string]interface{}{
						"valueFiles": valueFiles,
					},
				},
				"destination": map[string]interface{}{
					"server":    "https://kubernetes.default.svc",
					"namespace": "argocd",
				},
				"syncPolicy": map[string]interface{}{
					"automated": map[string]interface{}{
						"prune":    true,
						"selfHeal": true,
					},
					"syncOptions": []string{"CreateNamespace=true", "SkipDryRunOnMissingResource=true"},
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

func platformValueFiles(cfg *config.Config) ([]string, error) {
	raw := cfg.Get("platform.valueFiles")
	if raw == "" {
		return []string{"values.yaml", "values.doks.yaml"}, nil
	}
	var files []string
	if err := json.Unmarshal([]byte(raw), &files); err != nil {
		return nil, fmt.Errorf("platform.valueFiles must be a JSON array of strings: %w", err)
	}
	if len(files) == 0 {
		return nil, fmt.Errorf("platform.valueFiles is empty")
	}
	return files, nil
}
