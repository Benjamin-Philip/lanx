FROM pytorch/torchserve:latest

USER root
RUN apt-get update && apt-get install -y wget

USER model-server

RUN wget -q "https://download.pytorch.org/models/resnet50-0676ba61.pth"
RUN wget -q "https://raw.githubusercontent.com/pytorch/serve/refs/heads/master/examples/image_classifier/resnet_152_batch/model.py"
RUN wget -q "https://raw.githubusercontent.com/pytorch/serve/refs/heads/master/examples/image_classifier/resnet_152_batch/index_to_name.json"
RUN sed -i 's/ResNet152//g' model.py && sed -i 's/\[3\, 8\, 36\, 3\]/[3, 4, 6, 3]/g' model.py

RUN torch-model-archiver --model-name resnet50 --version 1.5 \
    --model-file model.py --serialized-file resnet50-0676ba61.pth \
    --export-path model-store --handler image_classifier \
    --extra-files index_to_name.json

RUN rm resnet50-0676ba61.pth model.py index_to_name.json

CMD ["torchserve", "--start", "--ncs", "--disable-token-auth", "--model-store", "model-store", " --models", "resnet50.mar"]
