# Machine learning project template
![11978-91-1536580089-2](https://user-images.githubusercontent.com/22550252/138448732-e867678f-c845-4428-a482-170412d08486.png)

## Preview
https://user-images.githubusercontent.com/22550252/143865452-c44cfb7d-12ee-4589-a5ed-5bac6a789965.mp4


## Requirements:
* [Docker with GPU support on Windows 10/11](https://github.com/lobantseff/template-ml-project/blob/master/docs/WINDOWS_DOCKER_GPU.md)
* [Docker with GPU support on Linux](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

## Installation

1. **Edit project requirements** in `environment.yaml`
2. **Build:**
* In Linux shell: `bash docker_build.sh`
* In Windows PowerShell: `.\docker_build.ps1`

3. **Run:**
* In Linux shell: `bash docker_run.sh`
* In Windows PowerShell: `.\docker_run.ps1`

  
**Notes:**
- You can [attach](https://code.visualstudio.com/docs/remote/containers) VSCode to a running container
- If you want to commit minor updates from a running container to the built image use:  
    `docker commit --change='CMD jupyter lab --no-browser' updated_container_name_or_hash docker_image_name`  
    (_not recommended as daily practice_)

## Project structure and philosophy behind

The idea behind this template is to be able to store lightweight code and heavy model artifacts and data in different places.

```
  # Code folder
  template-ml-project/
  ├── libs/
  |   ├── external_lib_as_submodule1/
  |   └── external_lib_as_submodule1/
  ├── src/
  │   ├── template_ml_project/
  │   │   └── __init__.py
  |   └── template_lib2/
  |       └── __init__.py
  ├── notebooks
  │   └── notebook_example.ipynb
  ├── .gitignore
  ├── Dockerfile
  ├── README.md
  ├── docker_build.ps1
  ├── docker_build.sh
  ├── docker_run.ps1
  ├── docker_run.sh
  ├── environment.yaml
  ├── set_jupyter_password.py
  └── setup.py
  
  # Workspace folder
  template-ml-project-workspace/
  ├── data_raw
      └── file.dcm
  ├── data_processed
      └── file.npz
  ├── artifacts
      ├── segmentation_masks
      |   └── mask.jpg
      └── checkpoints
  ├── configs/
  └── etc/
 ```
