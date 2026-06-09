# Attacker listener -- simple HTTP server that logs exfiltrated data
#
# Build:
#   docker build -t REGISTRY/openshell-poc/attacker-listener:latest \
#     images/attacker-listener/

FROM python:3.12-slim

COPY listener.py /app/listener.py

EXPOSE 9999

CMD ["python3", "/app/listener.py"]
