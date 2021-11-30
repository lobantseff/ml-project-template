FROM pytorch/pytorch:1.10.0-cuda11.3-cudnn8-runtime

ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Add user to avoid root access to attached dirs
ARG username=user
ARG groupname=user
ARG uid=1000
ARG gid=1000
RUN groupadd -g $gid $groupname \
    && useradd -u $uid -g $gid -s /bin/bash -d /home/$username $username \
    && mkdir /home/$username \
    && chown -R $username:$groupname /home/$username \
    && echo PATH=/opt/conda/bin:/opt/conda/condabin:$PATH >> /home/$username/.bashrc

# Install essential Linux packages
RUN apt-get update \
    && apt-get install -y build-essential git curl wget unzip vim screen \
    && rm -rf /var/lib/apt/lists/* \
    && conda init

# Install dependencies. Removing pytorch deps from yaml: they are already provided by the docker image.
COPY environment.yaml /root/conda_environment.yaml
RUN sed '/pytorch/d' /root/conda_environment.yaml > /root/tmp1.yaml \
    && sed '/torchvision/d' /root/tmp1.yaml > /root/tmp2.yaml \
    && sed '/cudatoolkit/d' /root/tmp2.yaml > /root/conda_environment.yaml \
    && rm -rf /root/tmp*.yaml
RUN conda env update -n base -f /root/conda_environment.yaml --prune \
    && conda clean --all --yes

# Configure Jupyter individually (to not to include in the requirements)
COPY --chown=$username:$groupname .jupyter_password set_jupyter_password.py /home/$username/.jupyter/
RUN conda install jupyterlab \
    && conda clean --all --yes
USER $username
RUN python /home/$username/.jupyter/set_jupyter_password.py $username

USER $username
WORKDIR /code
EXPOSE 8888

CMD ["jupyter", "lab", "--no-browser"]
