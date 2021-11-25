FROM pytorch/pytorch:1.10.0-cuda11.3-cudnn8-runtime

ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Add user to avoid root access to attached dirs
ARG username=user
ARG groupname=user
ARG uid=1000
ARG gid=1000
RUN groupadd -g $uid $groupname \
    && useradd -u $uid -g $gid -s /bin/bash -d /home/$username $username \
    && mkdir /home/$username \
    && chown -R $username:$groupname /home/$username

# Install essential Linux packages
RUN apt-get update \
    && apt-get install -y build-essential git curl wget unzip vim \
    && rm -rf /var/lib/apt/lists/* \
    && conda init

# Move conda to conda-forge
RUN conda config --add channels conda-forge \
    && conda config --remove channels defaults \
    && conda update -n base --yes conda

# Install dependencies. Removing pytorch deps from yaml: they are already provided by the docker image.
COPY environment.yaml /root/conda_environment.yaml
RUN sed '/pytorch/d' /root/conda_environment.yaml > /root/conda_environment.yaml \
    && sed '/torchvision/d' /root/conda_environment.yaml > /root/conda_environment.yaml \
    && sed '/cudatoolkit/d' /root/conda_environment.yaml > /root/conda_environment.yaml 
RUN conda env update -n base -f /root/conda_environment.yaml --prune \
    && conda clean --all --yes

# Configure Jupyter individually (to not to include in the requirements)
COPY --chown=$username:$groupname .jupyter_password set_jupyter_password.py /home/$username/.jupyter/
RUN conda install jupyterlab \
    && conda clean --all --yes
RUN su $username -c "python /home/$username/.jupyter/set_jupyter_password.py $username"

USER $username
WORKDIR /code
EXPOSE 8888

CMD ["jupyter", "lab", "--no-browser"]
