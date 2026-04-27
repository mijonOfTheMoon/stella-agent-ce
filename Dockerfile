# 构建层
FROM python:3.11.15-slim-trixie AS builder
RUN apt-get update && \
    apt-get install --no-install-suggests \
    --no-install-recommends --yes \
    python3-venv \
    gcc \
    libpython3-dev \
    libpq-dev \
    default-libmysqlclient-dev \
    make \
    && \
    python3 -m venv /root/venv && \
    /root/venv/bin/pip install --upgrade pip --trusted-host mirrors.aliyun.com --index-url https://mirrors.aliyun.com/pypi/simple

# Base 构建层
FROM builder AS builder-venv-base
RUN /root/venv/bin/pip install cffi --trusted-host mirrors.aliyun.com --index-url https://mirrors.aliyun.com/pypi/simple/

# 自定义构建层
FROM builder-venv-base AS builder-venv-custom
COPY requirements3.txt /root/requirements3.txt
RUN /root/venv/bin/pip install --disable-pip-version-check \
     	 --no-cache-dir \
         --trusted-host mirrors.aliyun.com \
         --index-url https://mirrors.aliyun.com/pypi/simple/ \
         -r /root/requirements3.txt

# Cython 编译层：在 builder 里完成 py2c.sh，避免把 gcc 带到 runner
FROM builder-venv-custom AS compiler
WORKDIR /root/df-llm-agent/
COPY ./df-llm-agent /root/df-llm-agent/
RUN chmod +x /root/df-llm-agent/py2c.sh && /root/df-llm-agent/py2c.sh

# 精简 venv：卸载仅构建期需要的 Cython，并清理 __pycache__ / *.pyc / build 产物
RUN /root/venv/bin/pip uninstall -y Cython && \
    find /root/venv -type d -name '__pycache__' -prune -exec rm -rf {} + && \
    find /root/venv -type f -name '*.pyc' -delete && \
    rm -rf /root/df-llm-agent/build

FROM python:3.11.15-slim-trixie AS runner

WORKDIR /root/df-llm-agent/

# 仅安装运行时必须的共享库（Postgres / MariaDB 客户端），并清理 apt 缓存
RUN apt-get update && \
    apt-get install --no-install-suggests --no-install-recommends --yes \
        libpq5 \
        libmariadb3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=compiler /root/venv /root/venv
COPY --from=compiler /root/df-llm-agent /root/df-llm-agent/
COPY ./etc/df-llm-agent.yaml /etc/web/

## dockerfile里的db_version 和issu里最大版本的x.x.x.x.sql 一致
ENV DB_VERSION=1.0.0.0

## Run
CMD ["/root/venv/bin/python3", "-u", "/root/df-llm-agent/app.py"]
