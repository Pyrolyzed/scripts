import os
import zipfile
import threading
import math
def exists(path):
    return os.path.isdir(path)


def make_if_not_exist(path):
    if (not exists(path)):
        os.makedirs(path)


def get_all_zips(path):
    zips = []
    path_encode = os.fsencode(path)
    for file in os.listdir(path_encode):
        filename = os.fsdecode(file)
        if filename.endswith(".zip") or filename.endswith(".rar"):
            zips.append(os.path.join(path, filename))
            continue
    return zips

def extract(file, location):
    with zipfile.ZipFile(file, 'r') as zip_ref:
        zip_ref.extractall(location)

input_lock = threading.Lock()
def thread_input(message):
    with input_lock:
        user_input = input(message)
        return user_input
    return ""
# Definitely code I wrote and not copied from stack overflow verbatim.
def chunks(lst, n):
    for i in range(0, len(lst), n):
        yield lst[i:i + n]

def process(zipfiles):
    for file in zipfiles:
        system = thread_input("What system is this for? " + file + " ")
        system_dir = os.path.join(roms_dir, system)
        make_if_not_exist(system_dir)
        extract(file, system_dir)
        romzips = get_all_zips(system_dir)
        for rom in romzips:
            extract(rom, system_dir)
            os.remove(rom)

# Main Program
staging_dir = input("What is the staging directory where your zipfiles are located?\n")
roms_dir = input("Where should the ROM files be extracted to?\n")

if (not exists(staging_dir)):
    print("Staging dir does not exist, please create it and fill it with zips.")
    exit()

make_if_not_exist(roms_dir)

thread_count = 4

zipfiles_chunks = list(chunks(get_all_zips(staging_dir), math.ceil(len(get_all_zips(staging_dir)) / thread_count)))

threads = []
for element in zipfiles_chunks:
    thread = threading.Thread(target=process, args=[element])
    threads.append(thread)
    thread.start()

for thread in threads:
    thread.join()

print("Done.")
