Automated Backup System (Bash Script).This Bash script automatically creates compressed backups of folders, verifies them, and removes older backups to save space. it make it easy to back up the files and restore theose if needed.

STEPS :

STEP 1 : Create the files in the folder. vi backup.config nano backup.sh documents folder (to test the backup on the dummy files in this folder).

STEP 2 : Make the script executable chmod +x backup.sh sudo chomod 777 backup.sh

STEP 3 : Edit backup.config accordingly to our requirements Save the file.

STEP 4 : Quick environment checks (make sure required commands exist) Run: command -v tar sha256sum md5sum shasum du df || true

STEP 5 : Run the backup ./backup.sh </path/to/source_folder> example: ./backup.sh --dry-run ./documents

What will happen: Archive backup-YYYY-MM-DD-HHMM.tar.gz will be created in BACKUP_DESTINATION. A checksum file ...tar.gz.md5 will be created. Verification will run and script prints SUCCESS on success. Actions (INFO/SUCCESS/ERROR) are appended to backup.log.

STEP 6 : Verify created files ls -lh ~/backups | grep backup - This shows the files that is in the backup folder with timestamp. cat "$HOME/backups/backup.log" - runs a dry-run test, then successfully created, verified, and restored a backup.

STEP 7 : Restore an archive to a folder: ./backup.sh --restore backup-2024-11-03-1430.tar.gz --to ~/restored_filesProject Test
<img width="931" height="328" alt="backup1" src="https://github.com/user-attachments/assets/e312cb80-f724-4788-a6b1-6260741927db" />
<img width="764" height="185" alt="backup2" src="https://github.com/user-attachments/assets/bc3a98d4-48b8-44dc-ad30-cc975cd5824b" />



