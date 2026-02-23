#!/usr/bin/env python3
import sys
import argparse
import requests
import tarfile
import tempfile
import re

BASE_URL = "https://api.github.com/repos/{0}/{1}/releases/{2}"

def create_arg_parser():
    parser = argparse.ArgumentParser(description="Downloads OnnxRuntime")

    parser.add_argument("--owner", type=str, required=True)
    parser.add_argument("--repo", type=str, required=True)
    parser.add_argument("--dir", type=str, required=True)
    parser.add_argument("--tag", type=str, required=True)
    parser.add_argument("--regex", type=str, required=True)

    return parser

def download_file(url, target_file):
    target_file.seek(0, 0)

    with requests.get(url, stream=True) as response:
        response.raise_for_status()
        for chunk in response.iter_content(chunk_size=8192):
            target_file.write(chunk)

    target_file.seek(0, 0)

def extract_tar(file, extract_loc):
    file.seek(0, 0)

    with tarfile.open(fileobj=file, mode="r:*") as as_tar:
        as_tar.extractall(path=extract_loc)

def determine_latest_release(owner, repo, tag, regex):
    formatted_url = BASE_URL.format(owner, repo, tag)
    response = requests.get(formatted_url, headers={"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
    response_data = response.json()

    for asset in response_data["assets"]:
        if re.match(regex, asset["name"]):
            return asset["browser_download_url"]

    raise Exception("Could not find a valid release candidate")

def main():
    parser = create_arg_parser()
    args = parser.parse_args()

    latest = determine_latest_release(args.owner, args.repo, args.tag, args.regex)
    with tempfile.SpooledTemporaryFile(mode='w+b') as temp_file:
        download_file(latest, temp_file)
        extract_tar(temp_file, args.dir)

    sys.exit(0)


if __name__ == "__main__":
    main()
