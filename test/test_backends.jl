ci_tol() =
    if Sys.islinux()
        is_pkgeval() ? "1e-2" : "5e-4"
    elseif Sys.isapple()
        "1e-3"
    else
        "1e-2"
    end

const TESTS_MODULE = Module(:PlotsTestsModule)
const PLOTS_IMG_TOL = parse(Float64, get(ENV, "PLOTS_IMG_TOL", is_ci() ? ci_tol() : "1e-5"))

# NOTE: don't use `plotly` (test hang, not surprised), test only the backends used in the docs
const CONCRETE_BACKENDS =
    :gr, :unicodeplots, :pythonplot, :pgfplotsx, :plotlyjs, :gaston, :inspectdr

Base.eval(TESTS_MODULE, :(using Random, StableRNGs, Plots))

reference_dir(args...) =
    if (ref_dir = get(ENV, "PLOTS_REFERENCE_DIR", nothing)) !== nothing
        ref_dir
    else
        joinpath(homedir(), ".julia", "dev", "PlotReferenceImages.jl", args...)
    end
reference_path(backend, version) = reference_dir("Plots", string(backend), string(version))

function checkout_reference_dir(dn::AbstractString)
    mkpath(dn)
    local repo
    for i in 1:6
        try
            repo = LibGit2.clone(
                "https://github.com/JuliaPlots/PlotReferenceImages.jl.git",
                dn,
            )
            break
        catch err
            @warn err
            sleep(20i)
        end
    end
    if (ver = Plots._current_plots_version).prerelease |> isempty
        try
            tag = LibGit2.GitObject(repo, "v$ver")
            hash = string(LibGit2.target(tag))
            LibGit2.checkout!(repo, hash)
        catch err
            @warn err
        end
    end
    LibGit2.peel(LibGit2.head(repo)) |> println  # print some information
    nothing
end

let dn = reference_dir()
    isdir(dn) || checkout_reference_dir(dn)
end

ref_name(i) = "ref" * lpad(i, 3, '0')

function reference_file(backend, version, i)
    # NOTE: keep ref[...].png naming consistent with `PlotDocs`
    refdir = reference_dir("Plots", string(backend))
    fn = ref_name(i) * ".png"
    reffn = joinpath(refdir, string(version), fn)
    for ver in sort(VersionNumber.(readdir(refdir)), rev = true)
        if (tmpfn = joinpath(refdir, string(ver), fn)) |> isfile
            reffn = tmpfn
            break
        end
    end
    return reffn
end

function image_comparison_tests(
    pkg::Symbol,
    idx::Int;
    debug = false,
    popup = !is_ci(),
    sigma = [1, 1],
    tol = 1e-2,
)
    example = Plots._examples[idx]
    @info "Testing plot: $pkg:$idx:$(example.header)"

    ver = Plots._current_plots_version
    ver = VersionNumber(ver.major, ver.minor, ver.patch)
    reffn = reference_file(pkg, ver, idx)
    newfn = joinpath(reference_path(pkg, ver), ref_name(idx) * ".png")

    imports = something(example.imports, :())
    exprs = quote
        Plots.debug!($debug)
        backend($(QuoteNode(pkg)))
        theme(:default)
        rng = StableRNG(Plots.PLOTS_SEED)
        $(Plots.replace_rand(example.exprs))
    end
    @debug imports exprs

    func = fn -> Base.eval.(Ref(TESTS_MODULE), (imports, exprs, :(png($fn))))
    test_images(
        VisualTest(func, reffn),
        newfn = newfn,
        popup = popup,
        sigma = sigma,
        tol = tol,
    )
end

function image_comparison_facts(
    pkg::Symbol;
    skip = [],          # skip these examples (int index)
    only = nothing,     # limit to these examples (int index)
    debug = false,      # print debug information ?
    sigma = [1, 1],     # number of pixels to "blur"
    tol = 1e-2,         # acceptable error (percent)
)
    for i in setdiff(1:length(Plots._examples), skip)
        if only === nothing || i in only
            @test success(image_comparison_tests(pkg, i; debug, sigma, tol))
        end
    end
end

## Uncomment the following lines to update reference images for different backends
#=

with(:gr) do
    image_comparison_facts(:gr, tol = PLOTS_IMG_TOL, skip = Plots._backend_skips[:gr])
end

with(:plotlyjs) do
    image_comparison_facts(:plotlyjs, tol = PLOTS_IMG_TOL, skip = Plots._backend_skips[:plotlyjs])
end

with(:pyplot) do
    image_comparison_facts(:pyplot, tol = PLOTS_IMG_TOL, skip = Plots._backend_skips[:pyplot])
end

with(:pgfplotsx) do
    image_comparison_facts(:pgfplotsx, tol = PLOTS_IMG_TOL, skip = Plots._backend_skips[:pgfplotsx])
end
=#

@testset "UnicodePlots" begin
    with(:unicodeplots) do
        @test backend() == Plots.UnicodePlotsBackend()

        io = IOContext(IOBuffer(), :color => true)

        # lets just make sure it runs without error
        pl = plot(rand(10))
        @test show(io, pl) isa Nothing

        pl = bar(randn(10))
        @test show(io, pl) isa Nothing

        pl = plot([1, 2], [3, 4])
        annotate!(pl, [(1.5, 3.2, Plots.text("Test", :red, :center))])
        hline!(pl, [3.1])
        @test show(io, pl) isa Nothing

        pl = plot([Dates.Date(2019, 1, 1), Dates.Date(2019, 2, 1)], [3, 4])
        hline!(pl, [3.1])
        annotate!(pl, [(Dates.Date(2019, 1, 15), 3.2, Plots.text("Test", :red, :center))])
        @test show(io, pl) isa Nothing

        pl = plot([Dates.Date(2019, 1, 1), Dates.Date(2019, 2, 1)], [3, 4])
        annotate!(pl, [(Dates.Date(2019, 1, 15), 3.2, :auto)])
        hline!(pl, [3.1])
        @test show(io, pl) isa Nothing

        pl = plot(map(plot, 1:4)..., layout = (2, 2))
        @test show(io, pl) isa Nothing

        pl = plot(map(plot, 1:3)..., layout = (2, 2))
        @test show(io, pl) isa Nothing

        pl = plot(map(plot, 1:2)..., layout = @layout([° _; _ °]))
        @test show(io, pl) isa Nothing

        redirect_stdout(devnull) do
            show(plot(1:2))
        end
    end
end

const blacklist = if VERSION.major == 1 && VERSION.minor ∈ (9, 10)
    [41]  # FIXME: github.com/JuliaLang/julia/issues/47261
else
    []
end

@testset "GR - reference images" begin
    with(:gr) do
        # NOTE: use `ENV["VISUAL_REGRESSION_TESTS_AUTO"] = true;` to automatically replace reference images
        @test backend() == Plots.GRBackend()
        @test backend_name() === :gr
        image_comparison_facts(
            :gr,
            tol = PLOTS_IMG_TOL,
            skip = vcat(Plots._backend_skips[:gr], blacklist),
        )
    end
end

@testset "Preferences" begin
    Plots.set_default_backend!()  # start with empty preferences

    withenv("PLOTS_DEFAULT_BACKEND" => "invalid") do
        @test_logs (:warn, r".*is not a supported backend") Plots.load_default_backend()
    end
    @test_logs (:warn, r".*is not a supported backend") backend(:invalid)

    @test Plots.load_default_backend() == Plots.GRBackend()

    withenv("PLOTS_DEFAULT_BACKEND" => "unicodeplots") do
        @test_logs (:info, r".*environment variable") Plots.diagnostics(devnull)
        @test Plots.load_default_backend() == Plots.UnicodePlotsBackend()
    end

    @test Plots.load_default_backend() == Plots.GRBackend()
    @test Plots.backend_package_name() === :GR
    @test Plots.backend_name() === :gr

    @test_logs (:info, r".*fallback") Plots.diagnostics(devnull)

    @test Plots.merge_with_base_supported([:annotations, :guide]) isa Set
    @test Plots.CurrentBackend(:gr).sym === :gr

    @test_logs (:warn, r".*is not compatible with") Plots.set_default_backend!(:invalid)

    @testset "persistent backend" begin
        # this test mimics a restart, which is needed after a preferences change
        Plots.set_default_backend!(:unicodeplots)
        script = tempname()
        write(
            script,
            """
            ENV["PLOTS_PRECOMPILE"] = false
            using Pkg, Test; io = (devnull, stdout)[1]  # toggle for debugging
            Pkg.activate(; temp = true, io)
            Pkg.develop(; path = "$(escape_string(pkgdir(Plots)))", io)
            Pkg.add("UnicodePlots"; io)  # checked by Plots
            using Plots
            res = @testset "Prefs" begin
                @test_logs (:info, r".*Preferences") Plots.diagnostics(io)
                @test backend() == Plots.UnicodePlotsBackend()
            end
            exit(res.n_passed == 2 ? 0 : 1)
            """,
        )
        @test success(run(```$(Base.julia_cmd()) $script```))
    end

    is_pkgeval() || for be in CONCRETE_BACKENDS
        (Sys.isapple() && be === :gaston) && continue  # FIXME: hangs
        @test_logs Plots.set_default_backend!(be)  # test the absence of warnings
        @test Base.compilecache(Base.module_keys[Plots]) isa String  # test default precompilation
    end

    Plots.set_default_backend!()  # clear `Preferences` key
end

is_pkgeval() || @testset "PlotlyJS" begin
    with(:plotlyjs) do
        @test backend() == Plots.PlotlyJSBackend()
        pl = plot(rand(10))
        @test pl isa Plot
        @test_broken display(pl) isa Nothing
    end
end

is_pkgeval() || @testset "Examples" begin
    callback(m, pkgname, i) = begin
        pl = m.Plots.current()
        save_func = (; pgfplotsx = m.Plots.pdf, unicodeplots = m.Plots.txt)  # fastest `savefig` for each backend
        fn = Base.invokelatest(
            get(save_func, pkgname, m.Plots.png),
            pl,
            tempname() * ref_name(i),
        )
        @test filesize(fn) > 1_000
    end
    Sys.islinux() && for be in CONCRETE_BACKENDS
        skip = vcat(Plots._backend_skips[be], blacklist)
        Plots.test_examples(be; skip, callback, disp = is_ci(), strict = true)  # `ci` display for coverage
        closeall()
    end
end
