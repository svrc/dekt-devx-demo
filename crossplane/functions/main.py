import sys
import requests
import yaml
import base64

def read_Functionio() -> dict:
    """Read the FunctionIO from stdin."""
    return yaml.load(sys.stdin.read(), yaml.Loader)

def write_Functionio(Functionio: dict):
    """Write the FunctionIO to stdout and exit."""
    sys.stdout.write(yaml.dump(Functionio))
    sys.exit(0)

def result_warning(Functionio: dict, message: str):
    """Add a warning result to the supplied FunctionIO."""
    if "results" not in Functionio:
        Functionio["results"] = []
    
    for r in Functionio["results"]:
      if r["severity"] != "Warning":
        continue
      if r["message"] == message:
        return
      
    Functionio["results"].append({"severity": "Warning", "message": message})

def result_normal(Functionio: dict, message: str):
    """Add a normal result to the supplied FunctionIO."""
    if "results" not in Functionio:
        Functionio["results"] = []
    
    for r in Functionio["results"]:
      if r["severity"] != "Normal":
        continue
      if r["message"] == message:
        return
        
    Functionio["results"].append({"severity": "Normal", "message": message})

def update_desired_resource(Functionio: dict, tap_view_b64: str):
    for r in Functionio["desired"]["resources"]:                      
        if r["name"] != "k8s-view-cluster-observe-secret":
            result_normal(
                Functionio,
                "skipping desired resource {name}".format(
                    name=r["name"]
                ),
            )       
            continue
        secret_manifest = r["resource"]["spec"]["forProvider"]["manifest"]
        if "data" not in secret_manifest:
            secret_manifest["data"] = {}
        secret_manifest["data"]["tap-view.yaml"] = tap_view_b64    
                  
def main():
   
    try:
        Functionio = read_Functionio()
    except yaml.parser.ParserError as err:
        sys.stdout.write("cannot parse FunctionIO: {}\n".format(err))
        sys.exit(1)
        
    if "desired" not in Functionio or "resources" not in Functionio["desired"]:
        result_normal(
            Functionio,
            "kicking back as desired/resources does not exist"
        )
        write_Functionio(Functionio)
 
    if "observed" not in Functionio or "resources" not in Functionio["observed"] or "composite" not in Functionio["observed"] or "resource" not in Functionio["observed"]["composite"]:
        result_normal(
            Functionio,
            "kicking back as observed/resources does not exist"
        )
        write_Functionio(Functionio)

    composite = Functionio["observed"]["composite"]["resource"]
    if "status" not in composite or "endpoint" not in composite["status"] or composite["status"]["endpoint"] == "":
        result_normal(
            Functionio,
            "kicking back as observed/composite/resource/status->endpoint does not exist or is empty"
        )
        write_Functionio(Functionio)
    
    cluster_url = composite["status"]["endpoint"]
    cluster_name = composite["spec"]["id"]
    cluster_token = ""
    
    
    for r in Functionio["observed"]["resources"]:
        if "name" not in r:
            # This shouldn't happen - add a warning and continue.
            result_warning(
                Functionio,
                "Observed Resource missing name"
            )
            continue
        
        if "resource" not in r:
            # This shouldn't happen - add a warning and continue.
            result_warning(
                Functionio,
                "Observed resource {name} missing resource body".format(
                    name=r.get("name", "unknown")
                ),  
            )
            continue        
        
        if r["name"] != "k8s-tap-gui-viewer-secret":
            result_normal(
                Functionio,
                "skipping observed resource {name}".format(
                    name=r["name"]
                ),
            )       
            continue
        
        if ("status" not in r["resource"] or 
            "atProvider" not in r["resource"]["status"] or 
            "manifest" not in r["resource"]["status"]["atProvider"] or
            "data" not in r["resource"]["status"]["atProvider"]["manifest"] or
            "token" not in r["resource"]["status"]["atProvider"]["manifest"]["data"]):
            result_normal(
                Functionio,
                "missing token on resource {resource}".format(
                    resource=r["resource"]
                ),
            )            
            write_Functionio(Functionio)
        else:        
            cluster_token_b64 = r["resource"]["status"]["atProvider"]["manifest"]["data"]["token"].encode('ascii')
            cluster_token = base64.b64decode(cluster_token_b64).decode('ascii')
        
            result_normal(
                Functionio,
                "Found {name} at {url} with secret {token}".format(
                    name=cluster_name,
                    url=cluster_url,
                    token=cluster_token
                ),  
            )
            
            for r in Functionio["observed"]["resources"]:
                      
                if r["name"] != "k8s-view-cluster-observe-secret":
                    result_normal(
                        Functionio,
                        "skipping desired resource {name}".format(
                            name=r["name"]
                        ),
                    )       
                    continue
                if ("status" not in r["resource"] or 
                    "atProvider" not in r["resource"]["status"] or 
                    "manifest" not in r["resource"]["status"]["atProvider"] or
                    "data" not in r["resource"]["status"]["atProvider"]["manifest"] or            
                    "tap-view.yaml" not in r["resource"]["status"]["atProvider"]["manifest"]["data"]):
                    result_normal(
                        Functionio,
                        "missing tap-view yaml on resource {resource}".format(
                            resource=r["resource"]
                        ),
                    )            
                    write_Functionio(Functionio)
                else:
                    tap_view_b64 = r["resource"]["status"]["atProvider"]["manifest"]["data"]["tap-view.yaml"]
                    tap_view = base64.b64decode(tap_view_b64).decode('ascii')
                    tap_view_yaml = yaml.load(tap_view, yaml.Loader)        
              
                    for c in tap_view_yaml["tap_gui"]["app_config"]["kubernetes"]["clusterLocatorMethods"]:
                        
                        if c["type"] != "config":
                            continue
                        else:
                            cluster_changed = False
                            for cluster in c["clusters"]:
                                if cluster["name"] != cluster_name:
                                    continue
                                else:
                                    if cluster["url"] != cluster_url:
                                        cluster["url"] = cluster_url
                                        cluster_changed = True
                                    if cluster["serviceAccountToken"] != cluster_token:
                                        cluster["serviceAccountToken"] = cluster_token
                                        cluster_changed = True                                        
                                    if cluster["skipTLSVerify"] != True:  
                                        cluster_changed = True
                                        cluster["skipTLSVerify"] = True 
                                    if cluster["authProvider"] != "serviceAccount":  
                                        cluster_changed = True
                                        cluster["authProvider"] = "serviceAccount" 
                                           
                                    if cluster_changed:
                                        
                                        tap_view = yaml.dump(tap_view_yaml)
                                        tap_view_b64 = base64.b64encode(tap_view.encode('ascii'))
                                        
                                        update_desired_resource(Functionio, tap_view_b64)
                                        result_normal(
                                            Functionio,
                                            "cluster {name} changed to url {url} and token {token}".format(
                                                name=cluster_name,
                                                url=cluster_url,
                                                token=cluster_token
                                            ),
                                        )     
                                        write_Functionio(Functionio)
                                    else:
                                        result_normal(
                                            Functionio,
                                            "cluster {name} not changed".format(
                                                name=cluster_name
                                            ),
                                        ) 
                                        write_Functionio(Functionio)
                                
                            c["clusters"].append({"name": cluster_name, 
                                "url": cluster_url, 
                                "serviceAccountToken": cluster_token,
                                "authProvider": "serviceAccount",
                                "skipTLSVerify": True})
                            tap_view = yaml.dump(tap_view_yaml)
                            tap_view_b64 = base64.b64encode(tap_view.encode('ascii')).decode('ascii')
                            update_desired_resource(Functionio, tap_view_b64)                        
                            result_normal(
                                Functionio,
                                "new cluster {name} added".format(
                                    name=cluster_name
                                ),
                            ) 
                            write_Functionio(Functionio)
                                
        
        
    result_normal(
        Functionio,
        "kicking back catch all"
    )        
    write_Functionio(Functionio)
  
  
if __name__ == "__main__":
    main()
