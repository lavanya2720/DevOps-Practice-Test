# Bash Scripting Project: Automated Backup System

## What You Will Build

You will create a backup tool that automatically saves copies of important files and folders. Think of it like a smart "copy and paste" that remembers what it copied, checks if the copy is good, and deletes old copies to save space.

---

## What Your Script Must Do

### Part 1: Create Backups (The Main Job)

Your script should:

1. **Take a folder as input** - The user tells your script which folder to backup
   - Example: `./backup.sh /home/user/my_documents`

2. **Create a compressed file** - Put all files into one `.tar.gz` file (like a ZIP file)
   - Name it with date and time: `backup-2024-11-03-1430.tar.gz`
   - This means: backup created on November 3rd, 2024 at 2:30 PM

3. **Save a "fingerprint" of the backup** - Create a checksum (a unique code that proves the file is not damaged)
   - Use MD5 or SHA256
   - Save it in a separate file: `backup-2024-11-03-1430.tar.gz.md5`

4. **Don't backup everything** - Skip unnecessary files like:
   - `.git` folders (Git version control files)
   - `node_modules` folders (JavaScript libraries)
   - `.cache` folders (temporary files)
   - Let users configure what to skip

---

### Part 2: Delete Old Backups (Keep Things Clean)

Your script should automatically delete old backups to save disk space:

**The Rules:**
- Keep the last 7 daily backups (one from each of the last 7 days)
- Keep the last 4 weekly backups (one from each of the last 4 weeks)
- Keep the last 3 monthly backups (one from each of the last 3 months)

**Example:**
```
Today is November 3rd
Daily backups: Nov 3, Nov 2, Nov 1, Oct 31, Oct 30, Oct 29, Oct 28
Weekly backups: Oct 27, Oct 20, Oct 13, Oct 6
Monthly backups: Oct 1, Sep 1, Aug 1
```

**Delete any backups older than these!**

---

### Part 3: Check If Backups Are Good (Verification)

After creating a backup:
1. **Calculate the checksum again** and compare with the saved one
2. **Try to extract a test file** from the backup to make sure it's not corrupted
3. **Print "SUCCESS"** if everything is okay, or **"FAILED"** if something is wrong

---

### Part 4: Make It Smart (Important Features)

#### A. Configuration File
- Don't put settings inside the script code
- Create a file called `backup.config` where users can set:
  - Where to save backups
  - Which folders to exclude
  - How many backups to keep
  - Email address for notifications (optional)

**Example `backup.config`:**
```bash
BACKUP_DESTINATION=/home/backups
EXCLUDE_PATTERNS=".git,node_modules,.cache"
DAILY_KEEP=7
WEEKLY_KEEP=4
MONTHLY_KEEP=3
```

#### B. Logging
- Save everything your script does to a log file: `backup.log`
- Include:
  - Date and time
  - What action was performed
  - If it succeeded or failed
  - Any error messages

**Example log:**
```
[2024-11-03 14:30:15] INFO: Starting backup of /home/user/documents
[2024-11-03 14:30:45] SUCCESS: Backup created: backup-2024-11-03-1430.tar.gz
[2024-11-03 14:30:46] INFO: Checksum verified successfully
[2024-11-03 14:30:50] INFO: Deleted old backup: backup-2024-10-05-0900.tar.gz
```

#### C. Dry Run Mode
- Let users test what the script will do WITHOUT actually doing it
- Usage: `./backup.sh --dry-run /home/user/documents`
- Print messages like: "Would backup folder X", "Would delete backup Y"

#### D. Prevent Multiple Runs
- What if someone runs the script twice at the same time?
- Use a lock file to prevent this
- Create a file like `/tmp/backup.lock` when script starts
- Check if this file exists before running
- Delete it when script finishes

---

## Extra Features (Bonus Points ⭐)

If you finish the main requirements, try these:

1. **Restore Function** - Add option to restore from a backup
   ```bash
   ./backup.sh --restore backup-2024-11-03-1430.tar.gz --to /home/user/restored_files
   ```

2. **List Backups** - Show all available backups with their sizes and dates
   ```bash
   ./backup.sh --list
   ```

3. **Space Check** - Before backing up, check if there's enough disk space

4. **Email Notifications** - Send an email when backup succeeds or fails (you can simulate this by writing to a file called `email.txt`)

5. **Incremental Backups** - Only backup files that changed since last backup (this is hard!)

---

## Things You Must Handle (Error Cases)

Your script should not crash! Handle these situations:

1. **Folder doesn't exist** - Print error: "Error: Source folder not found"
2. **No permission to read folder** - Print error: "Error: Cannot read folder, permission denied"
3. **Not enough disk space** - Print error: "Error: Not enough disk space for backup"
4. **Config file missing** - Use default values or print error
5. **Backup destination doesn't exist** - Create it automatically
6. **Script interrupted** - Clean up partial backup files

---

## What to Submit

### 1. Your Code
```
backup-system/
├── backup.sh              ← Your main script
├── backup.config          ← Configuration file
└── README.md              ← Documentation (very important!)
```

### 2. README.md Must Include

Write in simple English:

**A. Project Overview**
- What does your script do?
- Why is it useful?

**B. How to Use It**
- Installation steps
- Basic usage examples
- All command options explained

**C. How It Works**
- Explain your rotation algorithm (how you decide which backups to delete)
- Explain how you create checksums
- Show your folder structure for backups

**D. Design Decisions**
- Why did you choose this approach?
- What challenges did you face?
- How did you solve them?

**E. Testing**
- How did you test your script?
- Show example outputs

**F. Known Limitations**
- What doesn't work yet?
- What could be improved?

### 3. Examples You Must Show

Create a test folder with some files and demonstrate:
- Creating a backup
- Creating multiple backups over several "days" (you can fake the dates for testing)
- Automatic deletion of old backups
- Restoring from a backup (if you implemented this)
- Dry run mode
- Error handling (try to backup a folder that doesn't exist)

---

## How You Will Be Graded

| Category | Points | What We're Looking For |
|----------|--------|------------------------|
| Code Works Correctly | 30% | All main features work without errors |
| Code Quality | 25% | Clean code, good function names, comments, organized |
| Error Handling | 20% | Script doesn't crash, helpful error messages |
| Documentation | 15% | Clear README, good examples, explains everything |
| Configuration | 10% | Uses config file, not hardcoded values |

**Bonus points for extra features!**

---

## Hints to Get You Started

### Step 1: Start Simple
Don't try to do everything at once! Start with:
```bash
#!/bin/bash
# Just create a basic backup first
tar -czf backup-test.tar.gz /path/to/folder
```

### Step 2: Add Timestamp
```bash
TIMESTAMP=$(date +%Y-%m-%d-%H%M)
tar -czf backup-$TIMESTAMP.tar.gz /path/to/folder
```

### Step 3: Add Functions
Break your code into small functions:
```bash
create_backup() {
    # code here
}

verify_backup() {
    # code here
}

delete_old_backups() {
    # code here
}
```

### Step 4: Add Error Checking
```bash
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Directory does not exist"
    exit 1
fi
```

---

## Useful Commands You'll Need

- `tar -czf` - Create compressed archive
- `tar -xzf` - Extract archive
- `md5sum` or `sha256sum` - Create checksum
- `find` - Find files
- `date` - Get current date/time
- `df -h` - Check disk space
- `wc -l` - Count lines (useful for counting backups)
- `sort` - Sort files by name/date





## Final Tips

✅ **Test frequently** - Don't write everything then test at the end  
✅ **Use version control** - Commit to GitHub after each feature  
✅ **Read error messages carefully** - They tell you what's wrong  
✅ **Google is your friend** - Search for "bash how to..." when stuck  
✅ **Ask questions** - But try to solve it yourself first  
✅ **Write comments** - Explain what your code does  
✅ **Keep it simple** - Simple working code is better than complex broken code  

---

## Submission

Push your code to GitHub and share the link

Your repository should be well-organized and include:

✅ Working `backup.sh` script  
✅ Sample `backup.config` file  
✅ Detailed `README.md`  
✅ Example backup files (or screenshots)  
✅ Sample log output  

---

**Good luck! Remember: Start small, test often, and build incrementally. You've got this! 🚀**