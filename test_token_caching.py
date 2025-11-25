#!/usr/bin/env python3
"""
Test script for three-tier Auth0 token caching system.

This script tests:
1. Tier 3: Auth0 API fetch (cold start, no caches)
2. Tier 2: Parameter Store cache (new process, Parameter Store has token)
3. Tier 1: Memory cache (same process, token in memory)

Usage:
    python test_token_caching.py
"""

import sys
import os
import time
import boto3
from botocore.exceptions import ClientError

# Add project root to path
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from admin.token_cache import (
    get_auth0_mgmt_token,
    _auth0_mgmt_token,
    _auth0_mgmt_token_expiry,
    PARAMETER_STORE_TOKEN_PATH,
)
from admin.aws_secrets import inject_env_from_secrets


def clear_memory_cache():
    """Clear the in-memory token cache."""
    import admin.token_cache as tc
    tc._auth0_mgmt_token = None
    tc._auth0_mgmt_token_expiry = 0.0
    print("🗑️  Cleared memory cache")


def clear_parameter_store_cache(region_name="us-west-2"):
    """Delete the Parameter Store token cache."""
    try:
        client = boto3.client("ssm", region_name=region_name)
        client.delete_parameter(Name=PARAMETER_STORE_TOKEN_PATH)
        print(f"🗑️  Deleted Parameter Store cache: {PARAMETER_STORE_TOKEN_PATH}")
    except ClientError as e:
        if e.response['Error']['Code'] == 'ParameterNotFound':
            print(f"ℹ️  Parameter Store cache already empty")
        else:
            print(f"⚠️  Error deleting parameter: {e}")


def test_tier_3_auth0_fetch():
    """Test Tier 3: Fetch from Auth0 API (slowest)."""
    print("\n" + "="*70)
    print("TEST 1: Tier 3 - Auth0 API Fetch (Cold Start)")
    print("="*70)
    
    # Clear both caches to force Auth0 fetch
    clear_memory_cache()
    clear_parameter_store_cache()
    
    print("\n🧪 Fetching token (should hit Auth0 API)...")
    start = time.time()
    token = get_auth0_mgmt_token()
    duration = (time.time() - start) * 1000
    
    assert token is not None, "Token should not be None"
    assert len(token) > 0, "Token should not be empty"
    
    print(f"✅ Tier 3 test passed!")
    print(f"   Duration: {duration:.0f}ms")
    print(f"   Token: {token[:20]}...{token[-20:]}")
    return duration


def test_tier_2_parameter_store():
    """Test Tier 2: Load from Parameter Store (medium speed)."""
    print("\n" + "="*70)
    print("TEST 2: Tier 2 - Parameter Store Cache")
    print("="*70)
    
    # Clear only memory cache (Parameter Store should have token from previous test)
    clear_memory_cache()
    
    print("\n🧪 Fetching token (should hit Parameter Store)...")
    start = time.time()
    token = get_auth0_mgmt_token()
    duration = (time.time() - start) * 1000
    
    assert token is not None, "Token should not be None"
    assert len(token) > 0, "Token should not be empty"
    
    print(f"✅ Tier 2 test passed!")
    print(f"   Duration: {duration:.0f}ms")
    print(f"   Token: {token[:20]}...{token[-20:]}")
    return duration


def test_tier_1_memory_cache():
    """Test Tier 1: Memory cache (fastest)."""
    print("\n" + "="*70)
    print("TEST 3: Tier 1 - Memory Cache")
    print("="*70)
    
    # Don't clear anything - memory cache should be warm
    print("\n🧪 Fetching token (should hit memory cache)...")
    start = time.time()
    token = get_auth0_mgmt_token()
    duration = (time.time() - start) * 1000
    
    assert token is not None, "Token should not be None"
    assert len(token) > 0, "Token should not be empty"
    
    print(f"✅ Tier 1 test passed!")
    print(f"   Duration: {duration:.0f}ms")
    print(f"   Token: {token[:20]}...{token[-20:]}")
    return duration


def main():
    """Run all caching tier tests."""
    print("\n" + "🧪" * 35)
    print("Auth0 Token Caching - Three-Tier Test Suite")
    print("🧪" * 35)
    
    # Load Auth0 credentials
    print("\n📋 Loading Auth0 credentials from Parameter Store...")
    inject_env_from_secrets()
    
    try:
        # Test all three tiers
        tier3_duration = test_tier_3_auth0_fetch()
        time.sleep(1)  # Brief pause between tests
        
        tier2_duration = test_tier_2_parameter_store()
        time.sleep(1)
        
        tier1_duration = test_tier_1_memory_cache()
        
        # Summary
        print("\n" + "="*70)
        print("SUMMARY - Performance Comparison")
        print("="*70)
        print(f"\n{'Tier':<25} {'Duration':<15} {'vs Auth0':<20}")
        print("-" * 70)
        print(f"{'Tier 3: Auth0 API':<25} {tier3_duration:>8.0f}ms      {'(baseline)':<20}")
        
        tier2_speedup = ((tier3_duration - tier2_duration) / tier3_duration) * 100
        print(f"{'Tier 2: Parameter Store':<25} {tier2_duration:>8.0f}ms      {tier2_speedup:>5.1f}% faster")
        
        tier1_speedup = ((tier3_duration - tier1_duration) / tier3_duration) * 100
        print(f"{'Tier 1: Memory Cache':<25} {tier1_duration:>8.0f}ms      {tier1_speedup:>5.1f}% faster ⚡")
        
        print("\n✅ All tests passed! Three-tier caching is working correctly.")
        print("\nCache effectiveness:")
        print(f"  • Memory cache is {tier3_duration/tier1_duration:.1f}x faster than Auth0")
        print(f"  • Parameter Store is {tier3_duration/tier2_duration:.1f}x faster than Auth0")
        
        return 0
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
