FROM amazonlinux:2

# Setup build environment
RUN mkdir -p /build/src && \
    yum update -y && \
    # Add required packages
    yum install -y awscli curl git gcc gzip jq mariadb-devel openssl-devel postgresql-devel tree tar wget zip && \
    # help linker to find libmysqlclient later...
    ln -s /usr/lib64/mysql/libmysqlclient.so /usr/lib64/libmysqlclient.so && \
    # Install rust with rustup
    curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal

# Build environment setting
WORKDIR /build
ENV PATH=/root/.cargo/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Default build command
CMD \
  # Get latest web-vault release
  wget -O web-vault.tar.gz -q $(curl -s https://api.github.com/repos/dani-garcia/bw_web_builds/releases/latest  | \
    jq -r '.assets[] | select(.name | endswith ("tar.gz")) | .browser_download_url') && \
  tar -xf web-vault.tar.gz && rm web-vault.tar.gz && \
   # Build vaultwarden for al2
  cargo build --features sqlite,mysql,postgresql --release --target-dir target_al2 && \
  # Move built file and call it bootstrap
  mv target_al2/release/vaultwarden bootstrap && \
  # Optimizations and log linking
  strip --strip-all bootstrap && \
  size bootstrap && \
  ldd  bootstrap && \
  zip -9 -r bootstrap.zip bootstrap web-vault