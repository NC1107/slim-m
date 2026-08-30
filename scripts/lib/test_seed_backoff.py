# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for the seeding script's 429 backoff.

A fake sleep and a fake rng make this deterministic and instant: no test
here waits on a real clock, and the assertions are on how many times the
action and the sleep were actually called.
"""
import sys
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_backoff  # noqa: E402


def _http_error(code):
    return urllib.error.HTTPError("http://x", code, "boom", {}, None)


class CallWithBackoffTest(unittest.TestCase):
    def test_a_call_that_succeeds_first_try_never_sleeps(self):
        sleep = Mock()
        action = Mock(return_value="ok")
        got = seed_backoff.call_with_backoff(action, sleep=sleep)
        self.assertEqual(got, "ok")
        sleep.assert_not_called()

    def test_retries_past_429_and_returns_the_eventual_result(self):
        sleep = Mock()
        action = Mock(side_effect=[_http_error(429), _http_error(429), "ok"])
        got = seed_backoff.call_with_backoff(action, sleep=sleep, base_delay=1)
        self.assertEqual(got, "ok")
        self.assertEqual(action.call_count, 3)
        self.assertEqual(sleep.call_count, 2)

    def test_a_non_retryable_error_is_never_retried(self):
        sleep = Mock()
        action = Mock(side_effect=_http_error(400))
        with self.assertRaises(urllib.error.HTTPError):
            seed_backoff.call_with_backoff(action, sleep=sleep)
        self.assertEqual(action.call_count, 1)
        sleep.assert_not_called()

    def test_gives_up_and_reraises_once_max_attempts_is_spent(self):
        sleep = Mock()
        action = Mock(side_effect=_http_error(429))
        with self.assertRaises(urllib.error.HTTPError):
            seed_backoff.call_with_backoff(
                action, sleep=sleep, max_attempts=3, base_delay=1)
        self.assertEqual(action.call_count, 3)
        self.assertEqual(sleep.call_count, 2)

    def test_delay_grows_but_never_past_the_cap(self):
        rng = Mock()
        rng.random.return_value = 0.0
        sleep = Mock()
        action = Mock(side_effect=[_http_error(429)] * 4 + ["ok"])
        seed_backoff.call_with_backoff(
            action, sleep=sleep, base_delay=1, max_delay=3, rng=rng)
        delays = [call.args[0] for call in sleep.call_args_list]
        self.assertEqual(delays, [0.5, 1.0, 1.5, 1.5])


class IsRateLimitedTest(unittest.TestCase):
    def test_a_429_is_retryable(self):
        self.assertTrue(seed_backoff.is_rate_limited(_http_error(429)))

    def test_a_400_is_not(self):
        self.assertFalse(seed_backoff.is_rate_limited(_http_error(400)))

    def test_a_plain_exception_is_not(self):
        self.assertFalse(seed_backoff.is_rate_limited(ValueError("nope")))


if __name__ == "__main__":
    unittest.main()
