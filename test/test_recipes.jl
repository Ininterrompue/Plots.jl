using OffsetArrays

@testset "User recipes" begin
    struct LegendPlot end
    @recipe function f(plot::LegendPlot)
        legend --> :topleft
        (1:3, 1:3)
    end
    let pl = pl = plot(LegendPlot(); legend = :right)
        @test pl[1][:legend_position] === :right
    end
    let pl = pl = plot(LegendPlot())
        @test pl[1][:legend_position] === :topleft
    end
    let pl = plot(LegendPlot(); legend = :inline)
        @test pl[1][:legend_position] === :inline
    end
    let pl = plot(LegendPlot(); legend = :inline, ymirror = true)
        @test pl[1][:legend_position] === :inline
    end
end

@testset "lens!" begin
    pl = plot(1:5)
    lens!(pl, [1, 2], [1, 2], inset = (1, bbox(0.0, 0.0, 0.2, 0.2)), colorbar = false)
    @test length(pl.series_list) == 4
    @test pl[2][:colorbar] === :none
end

@testset "vline, vspan" begin
    vl = vline([1], widen = false)
    @test Plots.xlims(vl) == (1, 2)
    @test Plots.ylims(vl) == (1, 2)
    vl = vline([1], xlims = (0, 2), widen = false)
    @test Plots.xlims(vl) == (0, 2)
    vl = vline([1], ylims = (-3, 5), widen = false)
    @test Plots.ylims(vl) == (-3, 5)

    vsp = vspan([1, 3], widen = false)
    @test Plots.xlims(vsp) == (1, 3)
    @test Plots.ylims(vsp) == (0, 1) # TODO: might be problematic on log-scales
    vsp = vspan([1, 3], xlims = (-2, 5), widen = false)
    @test Plots.xlims(vsp) == (-2, 5)
    vsp = vspan([1, 3], ylims = (-2, 5), widen = false)
    @test Plots.ylims(vsp) == (-2, 5)
end

@testset "offset axes" begin
    tri = OffsetVector(vcat(1:5, 4:-1:1), 11:19)
    sticks = plot(tri, seriestype = :sticks)
    @test length(sticks) == 1
end

# NOTE: the following test seems to trigger these deprecated warnings:
# WARNING: importing deprecated binding Colors.RGB1 into PlotUtils.
# WARNING: importing deprecated binding Colors.RGB1 into Plots.
@testset "framestyle axes" begin
    pl = plot(-1:1, -1:1, -1:1)
    sp = pl.subplots[1]
    defaultret = Plots.axis_drawing_info_3d(sp, :x)
    for letter in (:x, :y, :z)
        for framestyle in [:box :semi :origin :zerolines :grid :none]
            prevha = UInt64(0)
            push!(sp.attr, :framestyle => framestyle)
            ret = Plots.axis_drawing_info_3d(sp, letter)
            ha = hash(string(ret))
            @test ha != prevha
            prevha = ha
        end
    end
end

@testset "coverage" begin
    @test :surface in Plots.all_seriestypes()
    @test Plots.seriestype_supported(Plots.UnicodePlotsBackend(), :surface) === :native
    @test Plots.seriestype_supported(Plots.UnicodePlotsBackend(), :hspan) === :recipe
    @test Plots.seriestype_supported(Plots.NoBackend(), :line) === :no
end

with(:gr) do
    @testset "error bars" begin
        x = y = 1:10
        yerror = fill(1, length(y))
        xerror = fill(0.2, length(x))
        p = Plots.xerror(x, y; xerror, linestyle = :solid)
        plot!(p, x, y; linestyle = :dash)
        yerror!(p, x, y; yerror, linestyle = :dot)
        @test length(p.series_list) == 3
        @test p[1][1][:linestyle] == :solid
        @test p[1][2][:linestyle] == :dash
        @test p[1][3][:linestyle] == :dot
    end

    @testset "parametric" begin
        @test plot(sin, sin, cos, 0, 2π) isa Plot
        @test plot(sin, sin, cos, collect((-2π):(π / 4):(2π))) isa Plot
    end

    @testset "dict" begin
        show(devnull, plot(Dict(1 => 2, 3 => -1)))
    end

    @testset "gray image" begin
        show(devnull, plot(rand(Gray, 2, 2)))
    end

    @testset "plots_heatmap" begin
        show(devnull, plots_heatmap(rand(RGBA, 2, 2)))
    end

    @testset "scatter3d" begin
        show(devnull, scatter3d(1:2, 1:2, 1:2))
    end

    @testset "sticks" begin
        show(devnull, sticks(1:2, marker = :circle))
    end

    @testset "stephist" begin
        show(devnull, stephist([1, 2], marker = :circle))
    end

    @testset "bar with logscales" begin
        show(devnull, bar([1 2 3], [0.02 125 10_000]; yscale = :log10))
    end
end
