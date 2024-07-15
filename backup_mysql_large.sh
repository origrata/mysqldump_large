#!/bin/bash
# Konfigurasi database
DB_USER="USERDB"
DB_PASSWORD="PASSWORDDB"
DB_HOST="localhost"
DB_NAME="NAMADB"

# Nama file output dengan timestamp
DATE=$(date +%Y%m%d%H%M%S)
TAR_FILE="backup_${DB_NAME}_${DATE}.tar.gz"

# Buat direktori sementara untuk menyimpan file SQL individual
TMP_DIR=$(mktemp -d)
if [ ! -d "$TMP_DIR" ]; then
  echo "Gagal membuat direktori sementara"
  exit 1
fi

# Fungsi untuk membuat dump tabel dengan pembagian baris
dump_table_in_chunks() {
  local table=$1
  local chunk_size=10000  # Sesuaikan chunk size sesuai kebutuhan
  local offset=0
  local part=0

  while true; do
    local sql_file="$TMP_DIR/${table}_part${part}.sql"
    mysql --user=$DB_USER --password=$DB_PASSWORD --host=$DB_HOST -e "SELECT * FROM $table LIMIT $chunk_size OFFSET $offset" $DB_NAME > $sql_file

    if [ $? -ne 0 ]; then
      echo "Gagal mengekspor bagian $part dari tabel $table"
      return 1
    fi

    if [ $(wc -c <"$sql_file") -eq 0 ]; then
      rm $sql_file
      break
    fi

    echo "Bagian $part dari tabel $table berhasil diekspor ke $sql_file"
    offset=$((offset + chunk_size))
    part=$((part + 1))
  done

  return 0
}

# Fungsi untuk membuat dump tabel dengan retry
dump_table() {
  local table=$1
  local max_retries=5
  local retry_count=0

  while [ $retry_count -lt $max_retries ]; do
    if dump_table_in_chunks $table; then
      return 0
    else
      echo "Gagal mengekspor tabel $table, percobaan $((retry_count+1)) dari $max_retries"
      retry_count=$((retry_count+1))
      sleep 5  # Tunggu 5 detik sebelum mencoba kembali
    fi
  done

  # Jika mencapai sini, semua percobaan gagal
  echo "Gagal mengekspor tabel $table setelah $max_retries percobaan"
  return 1
}

# Ambil daftar tabel dari database
tables=$(mysql --user=$DB_USER --password=$DB_PASSWORD --host=$DB_HOST -e "SHOW TABLES IN $DB_NAME" | tail -n +2)

# Lakukan dump untuk setiap tabel
for table in $tables; do
  if ! dump_table $table; then
    echo "Gagal mengekspor database"
    rm -r $TMP_DIR
    exit 1
  fi
done

# Gabungkan bagian-bagian file SQL menjadi satu file per tabel
for table in $tables; do
  cat $TMP_DIR/${table}_part*.sql > $TMP_DIR/${table}.sql
  rm $TMP_DIR/${table}_part*.sql
done

# Buat file tar.gz dari file SQL individual
tar -czvf $TAR_FILE -C $TMP_DIR .

# Periksa apakah tar berhasil
if [ $? -eq 0 ]; then
  echo "File SQL berhasil dikompres ke $TAR_FILE"
  # Hapus direktori sementara setelah diarsipkan
  rm -r $TMP_DIR
else
  echo "Gagal mengompres file SQL"
  rm -r $TMP_DIR
  exit 1
fi
