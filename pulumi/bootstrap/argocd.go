package bootstrap

import (
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/apiextensions"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	helmv3 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/helm/v3"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func NewProvider(ctx *pulumi.Context, kubeconfig pulumi.StringOutput) (*kubernetes.Provider, error) {
	return kubernetes.NewProvider(ctx, "turnkey-k8s", &kubernetes.ProviderArgs{
		Kubeconfig: kubeconfig,
	})
}

func InstallArgoCD(ctx *pulumi.Context, k8s *kubernetes.Provider) (*helmv3.Release, error) {
	ns, err := v1.NewNamespace(ctx, "argocd-namespace", &v1.NamespaceArgs{
		Metadata: metav1.ObjectMetaArgs{
			Name: pulumi.String("argocd"),
		},
	}, pulumi.Provider(k8s))
	if err != nil {
		return nil, err
	}

	release, err := helmv3.NewRelease(ctx, "argocd", &helmv3.ReleaseArgs{
		Name:      pulumi.String("argocd"),
		Namespace: ns.Metadata.Name().Elem(),
		RepositoryOpts: helmv3.RepositoryOptsArgs{
			Repo: pulumi.String("https://argoproj.github.io/argo-helm"),
		},
		Chart:   pulumi.String("argo-cd"),
		Version: pulumi.String("7.7.16"),
		Timeout: pulumi.Int(600),
	}, pulumi.Provider(k8s), pulumi.DependsOn([]pulumi.Resource{ns}))
	if err != nil {
		return nil, err
	}
	return release, nil
}

func ApplyRootApplication(ctx *pulumi.Context, k8s *kubernetes.Provider, argocdRelease *helmv3.Release, repoURL, revision, path string) error {
	var err error
	_, err = apiextensions.NewCustomResource(ctx, "argocd-root-app", &apiextensions.CustomResourceArgs{
		ApiVersion: pulumi.String("argoproj.io/v1alpha1"),
		Kind:       pulumi.String("Application"),
		Metadata: &metav1.ObjectMetaArgs{
			Name:      pulumi.String("turnkey-root"),
			Namespace: pulumi.String("argocd"),
		},
		OtherFields: kubernetes.UntypedArgs{
			"spec": map[string]interface{}{
				"project": "default",
				"source": map[string]interface{}{
					"repoURL":        repoURL,
					"targetRevision": revision,
					"path":           path,
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
