"""
Test script to verify orbital mechanics calculations for SOI entry point detection.

This simulates the same math used in orbiting_body.gd to find where a ship's
trajectory intersects another body's sphere of influence.
"""

import numpy as np
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
from matplotlib.patches import Circle

# =============================================================================
# Kepler's Equation Solvers (same as GDScript implementation)
# =============================================================================

def true_to_mean_anomaly(true_anomaly: float, eccentricity: float) -> float:
    """Convert true anomaly to mean anomaly (for elliptical orbits)."""
    e = eccentricity
    nu = true_anomaly
    
    # Eccentric anomaly: tan(E/2) = sqrt((1-e)/(1+e)) * tan(nu/2)
    half_nu = nu / 2.0
    tan_half_nu = np.tan(half_nu)
    factor = np.sqrt((1.0 - e) / (1.0 + e))
    tan_half_E = factor * tan_half_nu
    E = 2.0 * np.arctan(tan_half_E)
    
    # Mean anomaly: M = E - e*sin(E)
    M = E - e * np.sin(E)
    
    return M


def mean_to_true_anomaly(mean_anomaly: float, eccentricity: float, iterations: int = 10) -> float:
    """Convert mean anomaly to true anomaly using Newton-Raphson iteration."""
    M = mean_anomaly % (2 * np.pi)
    if M < 0:
        M += 2 * np.pi
    
    e = eccentricity
    
    # Solve Kepler's equation: M = E - e*sin(E) for E
    E = M  # Initial guess
    for _ in range(iterations):
        f = E - e * np.sin(E) - M
        f_prime = 1.0 - e * np.cos(E)
        if abs(f_prime) < 1e-10:
            break
        E = E - f / f_prime
        if abs(f) < 1e-10:
            break
    
    # Convert eccentric anomaly to true anomaly
    half_E = E / 2.0
    tan_half_E = np.tan(half_E)
    factor = np.sqrt((1.0 + e) / (1.0 - e))
    tan_half_nu = factor * tan_half_E
    nu = 2.0 * np.arctan(tan_half_nu)
    
    return nu


# =============================================================================
# Orbital Position Calculation
# =============================================================================

def get_position_at_time(t: float, M0: float, n: float, e: float, p: float, omega: float) -> np.ndarray:
    """
    Calculate position at time t given orbital elements.
    
    Args:
        t: Time since epoch
        M0: Mean anomaly at epoch
        n: Mean motion (rad/s)
        e: Eccentricity
        p: Semi-latus rectum
        omega: Argument of periapsis
    
    Returns:
        Position vector relative to central body
    """
    M = M0 + n * t  # Mean anomaly at time t
    nu = mean_to_true_anomaly(M, e)  # True anomaly at time t
    
    denom = 1.0 + e * np.cos(nu)
    if abs(denom) < 0.001:
        return np.array([np.inf, np.inf])
    
    r = p / denom
    if r <= 0 or not np.isfinite(r):
        return np.array([np.inf, np.inf])
    
    angle = nu + omega
    return np.array([r * np.cos(angle), r * np.sin(angle)])


def orbital_elements_to_params(a: float, e: float, omega: float, nu: float, mu: float):
    """
    Convert orbital elements to simulation parameters.
    
    Returns:
        (p, n, M0) - semi-latus rectum, mean motion, initial mean anomaly
    """
    p = a * (1.0 - e * e)  # Semi-latus rectum
    n = np.sqrt(mu / (a ** 3))  # Mean motion
    M0 = true_to_mean_anomaly(nu, e)  # Initial mean anomaly
    return p, n, M0


# =============================================================================
# SOI Entry Point Finding
# =============================================================================

def find_soi_entry_point(ship_params: dict, target_params: dict, target_soi: float, 
                          max_time: float, num_samples: int = 500):
    """
    Find where the ship's trajectory enters the target's SOI.
    
    Args:
        ship_params: dict with keys 'a', 'e', 'omega', 'nu', 'mu'
        target_params: dict with keys 'a', 'e', 'omega', 'nu', 'mu'
        target_soi: Sphere of influence radius
        max_time: Maximum simulation time
        num_samples: Number of time samples
    
    Returns:
        (entry_point, entry_time) or (None, None) if no intersection
    """
    # Get ship orbital parameters
    ship_a, ship_e, ship_omega, ship_nu = ship_params['a'], ship_params['e'], ship_params['omega'], ship_params['nu']
    ship_p, ship_n, ship_M0 = orbital_elements_to_params(ship_a, ship_e, ship_omega, ship_nu, ship_params['mu'])
    
    # Get target orbital parameters
    target_a, target_e, target_omega, target_nu = target_params['a'], target_params['e'], target_params['omega'], target_params['nu']
    target_p, target_n, target_M0 = orbital_elements_to_params(target_a, target_e, target_omega, target_nu, target_params['mu'])
    
    print(f"\n=== Ship Orbital Parameters ===")
    print(f"  Semi-major axis (a): {ship_a:.1f}")
    print(f"  Eccentricity (e): {ship_e:.4f}")
    print(f"  Argument of periapsis (ω): {np.degrees(ship_omega):.1f}°")
    print(f"  True anomaly (ν): {np.degrees(ship_nu):.1f}°")
    print(f"  Semi-latus rectum (p): {ship_p:.1f}")
    print(f"  Mean motion (n): {ship_n:.6f} rad/s")
    print(f"  Initial mean anomaly (M0): {np.degrees(ship_M0):.1f}°")
    
    print(f"\n=== Target Orbital Parameters ===")
    print(f"  Semi-major axis (a): {target_a:.1f}")
    print(f"  Eccentricity (e): {target_e:.4f}")
    print(f"  Argument of periapsis (ω): {np.degrees(target_omega):.1f}°")
    print(f"  True anomaly (ν): {np.degrees(target_nu):.1f}°")
    print(f"  Semi-latus rectum (p): {target_p:.1f}")
    print(f"  Mean motion (n): {target_n:.6f} rad/s")
    print(f"  Initial mean anomaly (M0): {np.degrees(target_M0):.1f}°")
    print(f"  SOI radius: {target_soi:.1f}")
    
    dt = max_time / num_samples
    was_outside = True
    
    for i in range(num_samples + 1):
        t = float(i) * dt
        
        # Ship position at time t
        ship_pos = get_position_at_time(t, ship_M0, ship_n, ship_e, ship_p, ship_omega)
        if not np.all(np.isfinite(ship_pos)):
            continue
        
        # Target position at time t  
        target_pos = get_position_at_time(t, target_M0, target_n, target_e, target_p, target_omega)
        if not np.all(np.isfinite(target_pos)):
            continue
        
        # Check distance
        dist = np.linalg.norm(ship_pos - target_pos)
        is_inside = dist < target_soi
        
        if is_inside and was_outside:
            # Found entry! Refine with binary search
            entry_point, entry_time = refine_entry_binary_search(
                t - dt, t,
                ship_M0, ship_n, ship_e, ship_p, ship_omega,
                target_M0, target_n, target_e, target_p, target_omega,
                target_soi
            )
            return entry_point, entry_time
        
        was_outside = not is_inside
    
    return None, None


def refine_entry_binary_search(t_low, t_high, 
                                ship_M0, ship_n, ship_e, ship_p, ship_omega,
                                target_M0, target_n, target_e, target_p, target_omega,
                                target_soi):
    """Binary search to find precise SOI entry point."""
    for _ in range(20):
        t_mid = (t_low + t_high) / 2.0
        
        # Ship position
        ship_pos = get_position_at_time(t_mid, ship_M0, ship_n, ship_e, ship_p, ship_omega)
        
        # Target position
        target_pos = get_position_at_time(t_mid, target_M0, target_n, target_e, target_p, target_omega)
        
        dist = np.linalg.norm(ship_pos - target_pos)
        
        if dist < target_soi:
            t_high = t_mid  # Entry is before this point
        else:
            t_low = t_mid  # Entry is after this point
        
        if abs(t_high - t_low) < 0.01:
            break
    
    t_entry = (t_low + t_high) / 2.0
    entry_point = get_position_at_time(t_entry, ship_M0, ship_n, ship_e, ship_p, ship_omega)
    return entry_point, t_entry


# =============================================================================
# Visualization
# =============================================================================

def visualize_orbits(ship_params: dict, target_params: dict, target_soi: float, 
                      entry_point=None, entry_time=None):
    """
    Visualize the orbits and SOI intersection.
    """
    fig, ax = plt.subplots(1, 1, figsize=(12, 12))
    
    # Get parameters
    ship_a, ship_e, ship_omega, ship_nu = ship_params['a'], ship_params['e'], ship_params['omega'], ship_params['nu']
    ship_p, ship_n, ship_M0 = orbital_elements_to_params(ship_a, ship_e, ship_omega, ship_nu, ship_params['mu'])
    
    target_a, target_e, target_omega, target_nu = target_params['a'], target_params['e'], target_params['omega'], target_params['nu']
    target_p, target_n, target_M0 = orbital_elements_to_params(target_a, target_e, target_omega, target_nu, target_params['mu'])
    
    # Draw central body (reference body)
    ax.plot(0, 0, 'yo', markersize=20, label='Central Body (Sun)')
    
    # Draw ship's full orbit (ellipse)
    ship_orbit_points = []
    for nu in np.linspace(0, 2*np.pi, 360):
        r = ship_p / (1.0 + ship_e * np.cos(nu))
        if r > 0:
            angle = nu + ship_omega
            ship_orbit_points.append([r * np.cos(angle), r * np.sin(angle)])
    ship_orbit_points = np.array(ship_orbit_points)
    ax.plot(ship_orbit_points[:, 0], ship_orbit_points[:, 1], 'b-', linewidth=1, alpha=0.5, label='Ship Orbit')
    
    # Draw target's full orbit
    target_orbit_points = []
    for nu in np.linspace(0, 2*np.pi, 360):
        r = target_p / (1.0 + target_e * np.cos(nu))
        if r > 0:
            angle = nu + target_omega
            target_orbit_points.append([r * np.cos(angle), r * np.sin(angle)])
    target_orbit_points = np.array(target_orbit_points)
    ax.plot(target_orbit_points[:, 0], target_orbit_points[:, 1], 'r-', linewidth=1, alpha=0.5, label='Target Orbit')
    
    # Draw current positions
    ship_pos_now = get_position_at_time(0, ship_M0, ship_n, ship_e, ship_p, ship_omega)
    target_pos_now = get_position_at_time(0, target_M0, target_n, target_e, target_p, target_omega)
    
    ax.plot(ship_pos_now[0], ship_pos_now[1], 'b^', markersize=15, label='Ship (now)')
    ax.plot(target_pos_now[0], target_pos_now[1], 'rs', markersize=12, label='Target (now)')
    
    # Draw target's SOI at current position
    soi_circle = Circle(target_pos_now, target_soi, fill=False, color='red', linestyle='--', linewidth=2, label='Target SOI (now)')
    ax.add_patch(soi_circle)
    
    # If we have an entry point, show positions at entry time
    if entry_point is not None and entry_time is not None:
        print(f"\n=== SOI Entry Found ===")
        print(f"  Entry time: {entry_time:.2f} seconds from now")
        print(f"  Ship entry position (relative to central body): ({entry_point[0]:.1f}, {entry_point[1]:.1f})")
        
        # Target position at entry time
        target_pos_entry = get_position_at_time(entry_time, target_M0, target_n, target_e, target_p, target_omega)
        print(f"  Target position at entry: ({target_pos_entry[0]:.1f}, {target_pos_entry[1]:.1f})")
        
        dist_at_entry = np.linalg.norm(entry_point - target_pos_entry)
        print(f"  Distance at entry: {dist_at_entry:.1f} (SOI = {target_soi:.1f})")
        
        # Draw entry point on ship's orbit
        ax.plot(entry_point[0], entry_point[1], 'g*', markersize=25, label=f'SOI Entry Point (t={entry_time:.1f}s)')
        
        # Draw target position at entry time
        ax.plot(target_pos_entry[0], target_pos_entry[1], 'mo', markersize=12, label=f'Target at entry (t={entry_time:.1f}s)')
        
        # Draw target's SOI at entry time
        soi_circle_entry = Circle(target_pos_entry, target_soi, fill=False, color='green', linestyle='-', linewidth=2, label='Target SOI at entry')
        ax.add_patch(soi_circle_entry)
        
        # Draw line from entry point to target at entry
        ax.plot([entry_point[0], target_pos_entry[0]], [entry_point[1], target_pos_entry[1]], 
                'g--', linewidth=1, alpha=0.7)
    else:
        print("\n=== No SOI Entry Found ===")
    
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper right')
    ax.set_title('Orbital Mechanics - SOI Entry Point Calculation')
    ax.set_xlabel('X (relative to central body)')
    ax.set_ylabel('Y (relative to central body)')
    
    # Set reasonable axis limits
    max_range = max(ship_a * (1 + ship_e), target_a * (1 + target_e)) * 1.2
    ax.set_xlim(-max_range, max_range)
    ax.set_ylim(-max_range, max_range)
    
    plt.tight_layout()
    plt.savefig('soi_intersection_test.png', dpi=150)
    print(f"\nPlot saved to: soi_intersection_test.png")
    # plt.show()  # Commented out for non-interactive mode


# =============================================================================
# Test Scenarios
# =============================================================================

def test_scenario_1():
    """
    Test scenario: Ship and planet both orbiting a star.
    Ship on transfer orbit designed to intercept the planet.
    """
    print("=" * 60)
    print("SCENARIO 1: Transfer orbit intercepting outer planet")
    print("=" * 60)
    
    # Common gravitational parameter (G * M_central)
    mu = 500000.0 * 20.0  # gravitational_constant * central_mass
    
    # Ship on an elliptical transfer orbit that reaches the planet's orbit
    # Apoapsis should be at the planet's orbital radius
    ship_params = {
        'a': 7000.0,        # Semi-major axis (average of inner and outer)
        'e': 0.15,          # Eccentricity - apoapsis ~8050, periapsis ~5950
        'omega': 0.0,       # Argument of periapsis (periapsis to the right)
        'nu': np.radians(0),  # Ship starts at periapsis
        'mu': mu
    }
    
    # Target planet on circular outer orbit
    # Position the planet so ship will reach it
    target_params = {
        'a': 8000.0,        # Semi-major axis (outer orbit)
        'e': 0.0,           # Eccentricity (circular)
        'omega': 0.0,       # Argument of periapsis
        'nu': np.radians(100),  # Planet position - ahead of ship
        'mu': mu
    }
    
    # Target SOI (using the formula from the game)
    target_mass = 5.0
    target_soi = 50.0 * np.sqrt(500000.0 * target_mass / 10000.0)
    # Make SOI larger to ensure intersection for testing
    target_soi = 1500.0  # Larger SOI for testing
    print(f"Target SOI (test): {target_soi:.1f}")
    
    # Calculate ship's orbital period for simulation time
    ship_period = 2 * np.pi * np.sqrt(ship_params['a']**3 / mu)
    print(f"Ship orbital period: {ship_period:.1f} seconds")
    
    # Ship apoapsis
    ship_apoapsis = ship_params['a'] * (1 + ship_params['e'])
    print(f"Ship apoapsis: {ship_apoapsis:.1f} (target orbit: {target_params['a']:.1f})")
    
    # Find SOI entry
    entry_point, entry_time = find_soi_entry_point(
        ship_params, target_params, target_soi,
        max_time=ship_period * 2,
        num_samples=500
    )
    
    # Visualize
    visualize_orbits(ship_params, target_params, target_soi, entry_point, entry_time)


def test_scenario_2():
    """
    Test with ship starting at a different position - behind the planet and catching up.
    """
    print("\n" + "=" * 60)
    print("SCENARIO 2: Ship chasing planet from behind")
    print("=" * 60)
    
    mu = 500000.0 * 20.0
    
    # Ship slightly behind the planet on an intersecting orbit
    ship_params = {
        'a': 7500.0,
        'e': 0.1,
        'omega': np.radians(0),  # Periapsis to the right
        'nu': np.radians(-30),   # Ship behind (negative angle)
        'mu': mu
    }
    
    # Planet ahead of ship on same side
    target_params = {
        'a': 8000.0,
        'e': 0.0,
        'omega': 0.0,
        'nu': np.radians(60),  # Planet ahead
        'mu': mu
    }
    
    target_soi = 1200.0  # Test SOI
    ship_period = 2 * np.pi * np.sqrt(ship_params['a']**3 / mu)
    
    entry_point, entry_time = find_soi_entry_point(
        ship_params, target_params, target_soi,
        max_time=ship_period * 2,
        num_samples=500
    )
    
    visualize_orbits(ship_params, target_params, target_soi, entry_point, entry_time)


def test_scenario_3():
    """
    Test with NEGATIVE true anomaly - important edge case!
    The GDScript may have issues with negative angles.
    """
    print("\n" + "=" * 60)
    print("SCENARIO 3: Negative true anomaly edge case")
    print("=" * 60)
    
    mu = 500000.0 * 20.0
    
    # Ship with negative true anomaly (just past apoapsis going down)
    ship_params = {
        'a': 7000.0,
        'e': 0.2,
        'omega': np.radians(45),  # Rotated orbit
        'nu': np.radians(-120),   # NEGATIVE - past apoapsis
        'mu': mu
    }
    
    target_params = {
        'a': 8000.0,
        'e': 0.0,
        'omega': 0.0,
        'nu': np.radians(-60),  # Also negative
        'mu': mu
    }
    
    target_soi = 1500.0
    ship_period = 2 * np.pi * np.sqrt(ship_params['a']**3 / mu)
    
    print(f"\nTesting negative true anomaly...")
    print(f"Ship true anomaly: {np.degrees(ship_params['nu']):.1f}°")
    print(f"Target true anomaly: {np.degrees(target_params['nu']):.1f}°")
    
    # Test the conversions with negative angles
    ship_M0 = true_to_mean_anomaly(ship_params['nu'], ship_params['e'])
    print(f"Ship M0 (from negative ν): {np.degrees(ship_M0):.1f}°")
    
    # Convert back
    ship_nu_back = mean_to_true_anomaly(ship_M0, ship_params['e'])
    print(f"Ship ν (converted back): {np.degrees(ship_nu_back):.1f}°")
    
    entry_point, entry_time = find_soi_entry_point(
        ship_params, target_params, target_soi,
        max_time=ship_period * 2,
        num_samples=500
    )
    
    visualize_orbits(ship_params, target_params, target_soi, entry_point, entry_time)


if __name__ == "__main__":
    test_scenario_1()
    test_scenario_2()
    test_scenario_3()  # Edge case with negative angles
