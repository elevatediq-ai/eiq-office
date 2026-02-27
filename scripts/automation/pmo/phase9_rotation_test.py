import asyncio
import os
import sys

# Add libs to path
sys.path.append(os.path.join(os.getcwd(), "libs"))

from governance import BackendType, secret_rotation_service


async def test_rotation_logging():
    """test_rotation_logging function."""
    print("🧪 Testing Secret Rotation Logging...")

    # We mock the rotation success but trigger the recording logic
    # In a real smoke test without cloud creds, we just test the DB part

    success = await secret_rotation_service.execute_rotation(
        secret_id="test-secret-123",  # noqa: S106
        backend_type=BackendType.AWS,
        triggered_by="smoke-test-user",
    )

    if success:
        print("✅ Rotation recorded successfully (or failed gracefully but logged)")
    else:
        print("❌ Rotation recording failed")


if __name__ == "__main__":
    asyncio.run(test_rotation_logging())
