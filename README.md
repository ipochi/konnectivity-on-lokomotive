# APIServer Network Proxy on Lokomotive (Equinix Metal only)

This installs apiserver-network-proxy on Lokomotive. Currently it only works on single master Lokomotive cluster
as on a single master apiserver is installed as a Deployment.


When creating a Lokomotive cluster add the `clc_snippet.yaml` to the cluster configuration in `controller_clc_snippets`

Example:

```hcl
  controller_clc_snippets = [
    file("./clc_snippet.yaml"),
  ]
```

Once the cluster is created, run the script

```hcl
ASSETS_DIR=<directory_containing_the_cluster_assets> ./install-konnectivity-on-lokomotive.sh
```

