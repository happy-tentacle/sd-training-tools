FROM runpod/kasm-docker:cuda11

RUN sudo mkdir -p /home/ht/training
RUN sudo chown -R kasm-user /home/ht/training

COPY ./run-trainer.sh /home/ht/training
COPY ./select-checkpoint.sh /home/ht/training
COPY ./install-and-run-trainer.sh /home/ht/training
COPY ./startup-install-and-run-trainer.sh /dockerstartup/custom_startup.sh