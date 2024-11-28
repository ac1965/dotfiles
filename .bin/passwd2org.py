#! /usr/bin/env python

import subprocess
import re

def get_keychain_passwords():
    """
    Get a list of saved passwords from macOS keychain.
    """
    try:
        # List all keychain items
        result = subprocess.run(['security', 'find-generic-password', '-a', '', '-w'], 
                                stdout=subprocess.PIPE, 
                                stderr=subprocess.PIPE, 
                                text=True)
        items = result.stdout.splitlines()
        return items
    except Exception as e:
        print(f"Error: {e}")
        return []

def format_as_org(passwords):
    """
    Format passwords as org entries.
    """
    org_entries = ["* Keychain Passwords"]
    for idx, pw in enumerate(passwords, 1):
        org_entries.append(f"** Entry {idx}\n   :PROPERTIES:\n   :PASSWORD: {pw}\n   :END:")
    return "\n".join(org_entries)

def save_to_org_file(content, filename="keychain_passwords.org"):
    """
    Save the org content to a file.
    """
    with open(filename, "w") as file:
        file.write(content)
    print(f"Passwords saved to {filename}")

if __name__ == "__main__":
    # Get the passwords
    passwords = get_keychain_passwords()
    
    if passwords:
        # Format as org
        org_content = format_as_org(passwords)
        
        # Save to file
        save_to_org_file(org_content)
    else:
        print("No passwords found or an error occurred.")
