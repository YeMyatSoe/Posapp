from rest_framework_simplejwt.tokens import RefreshToken
# ... other imports

def get_tokens_for_user(user):
    """
    Generates Access and Refresh tokens for a user, embedding role and shop_id 
    in the Access Token's payload.
    """
    refresh = RefreshToken.for_user(user)
    access_token = refresh.access_token

    # Add custom claims to the Access Token
    # Use getattr for safe access, assuming 'role' and 'shop_id' are fields on your user model
    access_token['role'] = getattr(user, 'role', None)
    
    # Safe check for shop_id: access shop.id only if user.shop exists
    if hasattr(user, 'shop') and user.shop is not None:
        access_token['shopId'] = user.shop.id
    else:
        access_token['shopId'] = None

    return {
        "refresh": str(refresh),
        "access": str(access_token),
        # Also return role/shopId directly for Flutter's immediate use on the client
        "role": access_token['role'],
        "shopId": access_token['shopId'],
    }

