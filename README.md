# all-language

A polyglot demo where one request fans down a chain of seven services, each calling the next:

**NodeJS → Python → Java → Golang → .NET → Ruby → PHP**

Every service returns a **nested JSON envelope** (so a single call shows the whole chain) and logs in **structured JSON**.

## Prerequisites

- A Kubernetes cluster and `kubectl`
- For a local cluster, `minikube` or `kind` works fine
- `jq` (optional, for pretty output)

> Images are prebuilt on Docker Hub (`kennethfoo49066/all-language-elastic-<service>`) and referenced in `all.yaml`, so you don't need to build anything to run this.

## Deploy

```bash
kubectl apply -f all.yaml
```

This creates a Deployment + Service for each language. NodeJS is exposed via a LoadBalancer; the rest are internal.

```bash
kubectl get pods        # wait until all are Running
kubectl get svc all-language-nodejs-lb
```

## Run it

Call the front of the chain using the NodeJS LoadBalancer address:

```bash
curl http://<EXTERNAL-IP>/nodejs | jq
```

You'll get a JSON response nested seven levels deep — each service wrapping the one it called, ending at php (`"upstream": null`).

> **Local cluster?** If `EXTERNAL-IP` stays `<pending>`, expose it with:
> `minikube service all-language-nodejs-lb --url`  (minikube), or
> `kubectl port-forward svc/all-language-nodejs-lb 8080:80` then `curl http://localhost:8080/nodejs`.

## View logs

Every service logs JSON on the same schema:

```bash
kubectl logs deploy/all-language-nodejs | jq
```

## Tear down

```bash
kubectl delete -f all.yaml
```
