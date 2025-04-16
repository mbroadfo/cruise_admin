FROM public.ecr.aws/lambda/python:3.9

# Copy app code
COPY lambdas/list_users.py ${LAMBDA_TASK_ROOT}
COPY admin ${LAMBDA_TASK_ROOT}/admin
COPY requirements.txt .

# Install only Python dependencies
RUN pip install -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

CMD ["list_users.lambda_handler"]
