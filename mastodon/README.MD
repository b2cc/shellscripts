## mastodon_manage_fediblock.sh
Quickly block/unblock domains across multiple Mastodon instances  
  
Options:  

    ~# bash ./mastodon_manage_fediblock.sh
        -a | --action     which action to invoke, can be one of:
                'block'   - block a remote instance
                'unblock' - unblock a remote instance
                'list'    - print list of instances currently managed by the script
        
        -c | --comment    comment to add to the block action (visible in admin web interface)
        -h | --help       display help
        -d | --domain     name of the domain which should be blocked/unblocked
        -s | --severity   how to block the instance, can be one of 'limit'/'silence' or 'suspend'


## ingress_update_bot_blocklist.sh
generate an ingress-nginx configmap block to block common scrapers
