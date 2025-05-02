FROM public.ecr.aws/lambda/python:3.11

# Set the working directory
WORKDIR /var/task

# Install OS packages
RUN yum install -y gcc && yum clean all

# Copy requirements and install
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy your FastAPI app code
COPY app/ ./app/
COPY admin/ ./admin/

# Tell Lambda which handler to call (we'll explain below)
CMD ["main.lambda_handler"]
