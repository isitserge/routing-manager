#!/usr/bin/env python3

import ipaddress
import sys

def calculate_subnet_cutouts(network_str, exclusions):
    """
    Calculate subnet cutouts that cover the network while avoiding exclusions.
    
    Args:
        network_str: Network in CIDR format (e.g., "10.0.0.0/8")
        exclusions: List of excluded networks in CIDR format
    
    Returns:
        List of subnet cutouts that avoid the exclusions
    """
    try:
        # Parse the main network
        main_network = ipaddress.ip_network(network_str, strict=False)
        
        # Parse exclusions
        excluded_networks = []
        for exc in exclusions:
            try:
                excluded_networks.append(ipaddress.ip_network(exc, strict=False))
            except:
                continue
        
        # Use ipaddress's built-in address_exclude method for precise calculation
        remaining_networks = [main_network]
        
        # For each exclusion, subtract it from all remaining networks
        for excluded in excluded_networks:
            new_remaining = []
            for network in remaining_networks:
                try:
                    # If the excluded network is within this network, subtract it
                    if excluded.subnet_of(network):
                        # Use address_exclude to get the remaining subnets
                        cutouts = list(network.address_exclude(excluded))
                        new_remaining.extend(cutouts)
                    else:
                        # If exclusion doesn't overlap, keep the original network
                        new_remaining.append(network)
                except:
                    # If there's any error, keep the original network
                    new_remaining.append(network)
            remaining_networks = new_remaining
        
        # Convert back to strings and sort
        result = [str(net) for net in remaining_networks]
        result.sort()
        return result
        
    except Exception as e:
        print(f"Error calculating cutouts: {e}", file=sys.stderr)
        return [network_str]  # Fallback to original network

def main():
    if len(sys.argv) < 2:
        print("Usage: subnet-calculator.py <network> [exclusion1] [exclusion2] ...", file=sys.stderr)
        sys.exit(1)
    
    network = sys.argv[1]
    exclusions = sys.argv[2:] if len(sys.argv) > 2 else []
    
    cutouts = calculate_subnet_cutouts(network, exclusions)
    
    for cutout in cutouts:
        print(cutout)

if __name__ == "__main__":
    main()